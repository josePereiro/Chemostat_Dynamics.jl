using Chemostat_Dynamics
using Chemostat_Dynamics.LP_Implement
using ProgressMeter
using Plots
using Serialization

## ---------------------------------------------------------
# SimTools
function vrange(L, U, d::Int)
    dx = 10.0^(-d)
    x0 = round(L, RoundUp; digits = d)
    x1 = round(U, RoundDown; digits = d)
    return x0:dx:x1
end

cache_file(name, args...) = joinpath(@__DIR__, string(name, hash(args), ".jld"))

function vgvatp_caches(net, θvg, θvatp, 
        vg_idx, vatp_idx)  
    
    # ranges
    vatpL, vatpU = fva(net, vatp_idx)
    vatp_range = vrange(vatpL, vatpU, θvatp)
    vg_ranges = Dict()
    for vatp in vatp_range
        vgL, vgU = fixxing(net, vatp_idx, vatp) do 
            fva(net, vg_idx)
        end
        vg_ranges[vatp] = vrange(vgL, vgU, θvg)
    end
    
    prog2 = Progress(sum(length.(values(vg_ranges))); 
        desc = "Caching... ", dt = 0.1)
    cache = Dict{Tuple{Float64,Float64}, Vector{Float64}}()
    for vatp in vatp_range
        for vg in vg_ranges[vatp]
            fixxing(net, vatp_idx, vatp) do 
                fixxing(net, vg_idx, vg) do 
                    cache[(vg, vatp)] = fba(net, vg_idx)
                    next!(prog2)                
                    return nothing
                end
            end
        end
    end
    finish!(prog2)
    return cache
end

## ---------------------------------------------------------
function run_simulation(;
        # Sim params
        θvatp = 2,
        θvg = 3,
        X0 = 1e-3,
        Xmin = 1e-6,
        
        cg = 15.0,
        sg = 15.0,
        Kg = 0.5,
        Vg = 0.5,

        cl = 0.0,
        sl = 0.0,
        Kl = 0.0,
        Vl = 0.0, # 0.1

        D = 1e-2,
        ϵ = 0.0,
        niters = 200,
        damp = 0.9
    )

    ## ---------------------------------------------------------
    # model
    net = ToyModel()
    vatp_idx = rxnindex(net, "vatp")
    vg_idx = rxnindex(net, "gt")
    vl_idx = rxnindex(net, "lt")
    obj_idx = rxnindex(net, "biom")
    net.ub[vg_idx] = max(net.lb[vg_idx], (Vg * sg) / (Kg + sg))
    net.ub[vl_idx] = max(net.lb[vl_idx], (Vl * sl) / (Kl + sl))

    ## ---------------------------------------------------------
    # Polytope cache
    cfile = cache_file("cache", hash(net), θvatp, θvg)
    if !isfile(cfile)
        cache = vgvatp_caches(net, θvg, θvatp, vg_idx, vatp_idx)
        serialize(cfile, cache)
    else
        cache = deserialize(cfile)
    end
    
    sl_ts = []
    sg_ts = []
    X_ts = []
    Xb = Dict{Tuple{Float64,Float64}, Float64}()

    
    prog = Progress(niters)
    for it in 1:niters

        ## ---------------------------------------------------------
        # ranges
        vatpL, vatpU = fva(net, vatp_idx)
        vatp_range = vrange(vatpL, vatpU, θvatp)
        vg_ranges = Dict()
        for vatp in vatp_range
            vgL, vgU = fixxing(net, vatp_idx, vatp) do 
                fva(net, vg_idx)
            end
            vg_ranges[vatp] = vrange(vgL, vgU, θvg)
        end

        ## ---------------------------------------------------------
        # X
        if isempty(Xb) 
            for vatp in vatp_range
                for vg in vg_ranges[vatp]
                    get!(Xb, (vg, vatp), X0) # Init
                end
            end
        end

        z = Dict{Float64, Float64}()
        Σvg__X = Dict{Float64, Float64}()
        vgN = Dict{Float64, Int}()

        for vatp in vatp_range
            Σvg__X[vatp] = 0.0
            vg_range = vg_ranges[vatp]
            for vg in vg_range
                lX = get!(Xb, (vg, vatp), Xmin)
                Σvg__X[vatp] += lX
            end

            z[vatp] = cache[(first(vg_range), vatp)][obj_idx]
            vgN[vatp] = length(vg_range)
        end

        Σ_vatp_vg__z_X = sum(z[vatp]* Σvg__X[vatp] for vatp in vatp_range)
        vatpvgN = sum(values(vgN))
        term2 = ϵ * (Σ_vatp_vg__z_X) / vatpvgN

        for vatp in vatp_range
            term1 = (1 - ϵ) * (z[vatp]* Σvg__X[vatp]) / vgN[vatp]
            for vg in vg_ranges[vatp]
                k = (vg, vatp)
                lX = Xb[k]
                term3 = lX * D
                # update X
                lX = (damp * lX) + (1 - damp) * (lX + term1 + term2 - term3) 
                Xb[k] = max(Xmin, lX)
            end
        end
        
        ## ---------------------------------------------------------
        # Update Xb
        temp_Xb = Xb
        Xb = Dict{Tuple{Float64,Float64}, Float64}()
        for vatp in vatp_range
            for vg in vg_ranges[vatp]
                k = (vg, vatp)
                Xb[k] = temp_Xb[k]
            end
        end
        X = sum(values(Xb))

        ## ---------------------------------------------------------
        # concs
        Σ_vatp_vg__vg_X = 0.0
        Σ_vatp_vg__vl_X = 0.0
        for vatp in vatp_range
            for vg in vg_ranges[vatp]
                k = (vg, vatp)
                vl = cache[k][vl_idx]

                lX = Xb[k]
                Σ_vatp_vg__vg_X += vg * lX
                Σ_vatp_vg__vl_X += vl * lX
            end
        end
        # update sg
        dsg = -Σ_vatp_vg__vg_X + D*(cg - sg)
        sg = max(0.0, damp * sg + (1 - damp) * (sg + dsg))
        # update sl
        dsl = -Σ_vatp_vg__vl_X + D*(cl - sl)
        sl = max(0.0, damp * sl + (1 - damp) * (sl + dsl))
        

        ## ---------------------------------------------------------
        # Store
        push!(X_ts, X)
        push!(sl_ts, sl)
        push!(sg_ts, sg)

        ## ---------------------------------------------------------
        # Update polytope
        net.ub[vg_idx] = max(net.lb[vg_idx], (Vg * sg) / (Kg + sg))

        ## ---------------------------------------------------------
        # Verbose
        update!(prog, it; showvalues = [
                (:X, X),
                (:sg, sg),
                (:dsg, dsg),
                (:sl, sl),
                (:dsl, dsl),
                (:vg_ub, net.ub[vg_idx]),
                (:vatpvgN, vatpvgN),
                (:Xb_len, length(Xb)),
                (:damp, damp)
            ]
        )

    end # for it in 1:niters
    finish!(prog)

    X_ts, sg_ts, sl_ts, Xb
end

## ---------------------------------------------------------
let
    X_ts, sg_ts, sl_ts, Xb = run_simulation(
        D = 5e-4, 
        X0 = 5e-5, 
        Xmin = 1e-20, 
        niters = 100, 
        damp = 0.9,
        ϵ = 0.0,
    )
    p1 = plot(xlabel = "time", ylabel = "conc")
    plot!(p1, sg_ts; label = "sg", lw = 3)
    plot!(p1, sl_ts; label = "sl", lw = 3)
    
    p2 = plot(xlabel = "time", ylabel = "X")
    plot!(p2, X_ts; label = "X", lw = 3)
    
    plot([p1, p2]...)
end