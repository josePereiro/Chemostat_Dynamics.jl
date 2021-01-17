import DrWatson: quickactivate
quickactivate(@__DIR__, "Chemostat_InSilico")

@time begin

    import Chemostat_InSilico
    const InCh = Chemostat_InSilico
    const InLP = InCh.LP_Implement
    const InU = InCh.Utilities

    using ProgressMeter
    using Plots
    using Plots.Measures

    # Test
    # import GR
    # GR.inline("png")

    import UtilsJL
    const UJL = UtilsJL

    using Serialization
    using Base.Threads
    using Dates
    using Statistics
    using InteractiveUtils
    using Random
    using Colors

end

## ----------------------------------------------------------------------------
# Meta
fileid = "2.2"
minmax(a) = isempty(a) ? (0.0, 0.0) : (minimum(a), maximum(a))

## ----------------------------------------------------------------------------
# Prepare network
const STST_POL = :STST_POL   # Use polytope computed from chemostat stst assertion
const DYN_POL = :DYN_POL     # Use dynamic polytope
const HOMO = :HOMO           # Do not use extra constraints
const HETER = :HETER         # Match ME and Dy biom average
const FIXXED = :FIXXED       # Fix biom around observed

MOD_COLORS = Dict(
    HOMO => :red, 
    FIXXED => :orange,
    HETER => :blue,
)

POL_STYLE = Dict(
    STST_POL => :dot,
    DYN_POL => :dash,
)

## ----------------------------------------------------------------------------
# Marginals
# MDAT[MODsym, POLTsym, :M, Vl, D, ϵ, τ]
# MDAT[MODsym, POLTsym, :MEMs, Vl, D, ϵ, τ]
# MDAT[MODsym, POLTsym, :beta0, Vl, D, ϵ, τ]
# MDAT[:STATUS, Vl, D, ϵ]
MINDEX = UJL.load_data(InCh.MARGINALS_INDEX_FILE)
POLTsym = STST_POL
EXP_PARAMS = Iterators.product(MINDEX[[:Vls, :Ds, :ϵs, :τs]]...);

function getdat(dk, dks...)
    FILE = MINDEX[:DFILE, dks...]
    if FILE isa UJL.ITERABLE
        dat = []
        for F in FILE
            datum = deserialize(F)[dk...]
            push!(dat, datum)
        end
        return dat
    else
        dat = deserialize(FILE)
        return dat[dk...]
    end
end

## ----------------------------------------------------------------------------
# PLOTS
PS = UJL.DictTree()
function mysavefig(p, pname; params...)
    pname = UJL.mysavename(pname, "png"; params...)
    fname = joinpath(InLP.DYN_FIGURES_DIR, string(fileid, "_", pname))
    savefig(p, fname)
    PS[pname] = deepcopy(p)
    @info "Plotting" fname
end

## ----------------------------------------------------------------------------
# Plot functions
function plot_pol!(p, POLTsym, MODsym, Vl, D, ϵ, τ; sparams...)
    
    vatp_range, vg_ranges = getdat([MODsym, POLTsym, :POL], Vl, D, ϵ, τ)
    vatps, vgLs, vgUs = [], [], []
    
    for (vatpi, vatp) in enumerate(vatp_range)
        vg_range = vg_ranges[vatpi]
        isempty(vg_range) && continue
        vgL, vgU = minmax(vg_range)
        push!(vatps, vatp)
        push!(vgLs, vgL)
        push!(vgUs, vgU)
    end

    color = MOD_COLORS[MODsym]
    ls = POL_STYLE[POLTsym]
    plot!(p, [vatps], [vgLs]; label = "", ls, alpha = 0.4, color, lw = 3, sparams...)
    plot!(p, [vatps], [vgUs]; label = "", ls, alpha = 0.4, color, lw = 3, sparams...)
    PS[MODsym, POLTsym, :POL, Vl, D, ϵ] = deepcopy(p)
    p
end

function plot_marginals!(p, MODsyms, POLTsym, rxn, Vl, D, ϵ, τ; sparams...)

    ls = POL_STYLE[POLTsym]
    DyMs = getdat([:DyMs], Vl, D, ϵ, τ)
    plot!(p, DyMs[rxn]; label = "", sparams..., color = :black)
    
    # Marginals
    for MODsym in MODsyms
        color = MOD_COLORS[MODsym]
        MEMs = getdat([MODsym, POLTsym, :MEMs], Vl, D, ϵ, τ)
        plot!(p, MEMs[rxn]; label = "", color, sparams...)
        PS[MODsym, POLTsym, :POL, Vl, D, ϵ] = deepcopy(p)
    end
    p
end
plot_marginals!(p, MODsyms::Symbol, POLTsym, rxn, Vl, D, ϵ, τ; sparams...) = 
    plot_marginals!(p, [MODsyms], POLTsym, rxn, Vl, D, ϵ, τ; sparams...)

## ----------------------------------------------------------------------------
# # Polytopes
# let
#     sparams =(;alpha = 0.5, lw = 5, ylim = [0.0, Inf])

#     for (Vl, D, ϵ, τ) in EXP_PARAMS
#         MINDEX[:STATUS, Vl, D, ϵ, τ] == :death && continue
#         for MODsym = [HOMO, FIXXED, HETER]
#             p = plot(;title = "polytope", xlabel = "vatp", ylabel = "vg")        
#             for POLTsym in [STST_POL, DYN_POL]
#                 plot_pol!(p, POLTsym, MODsym, Vl, D, ϵ, τ; sparams...)
#             end
            
#             mysavefig(p, "Polytopes_$(POLTsym)_$(MODsym)"; Vl, D, ϵ, τ)
#         end
#     end
# end

## ----------------------------------------------------------------------------
# all Marginals
let
   
    for (Vl, D, ϵ, τ) in EXP_PARAMS
        MINDEX[:STATUS, Vl, D, ϵ, τ] == :death && continue
        ps = []
        sparams =(;alpha = 0.8, lw = 5, ylim = [0.0, Inf])
        gparams = (xaxis = nothing, yaxis = nothing, grid = false, 
                titlefont = 10, xaxisfont = 10,
                bottom_margin = 5mm, top_margin = 8mm,
                left_margin = 5mm, right_margin = 5mm
            )
        for rxn in InLP.RXNS
            p = plot(;title = rxn, xlabel = "flx", ylabel = "prob", gparams...)
            for  MODsym = [FIXXED, HETER, HOMO]
                plot_marginals!(p, MODsym, POLTsym, rxn, Vl, D, ϵ, τ; sparams...)
            end
            push!(ps, p)
        end

        p = plot(;title = "polytope", xlabel = "vatp", ylabel = "vg", gparams...)        
        plot_pol!(p, POLTsym, HETER, Vl, D, ϵ, τ; sparams...)
        plot_pol!(p, POLTsym, HOMO, Vl, D, ϵ, τ; sparams...)
        plot_pol!(p, POLTsym, FIXXED, Vl, D, ϵ, τ; sparams...)
        push!(ps, p)
        
        p = plot(ps...; layout = length(ps))
        mysavefig(p, "Marginals_$(POLTsym)_"; Vl, D, ϵ)
    end
end

## ----------------------------------------------------------------------------
# selected Marginals
let
    Vl = MINDEX[:Vls] |> first
    τ = MINDEX[:τs] |> first
    D = (MINDEX[:Ds] |> sort)[3]
    ϵs = MINDEX[:ϵs] |> sort
    sparams =(;alpha = 0.8, lw = 5, ylim = [0.0, Inf])
    gparams = (grid = false, titlefont = 10, xaxisfont = 10, 
        bottom_margin = 5mm, top_margin = 8mm,
        left_margin = 5mm, right_margin = 5mm
    )
    
    ps = []
    for ϵ in ϵs
        for rxn in ["gt", "vatp"]
            MINDEX[:STATUS, Vl, D, ϵ, τ] == :death && continue
            @info "Doing" rxn, Vl, D, ϵ, τ
            p = plot(;title = "ϵ = $ϵ", 
                xlabel = rxn == "gt" ? "vg" : rxn, 
                ylabel = "prob", gparams...
            )
            @time begin
                plot_marginals!(p, [HOMO, HETER, FIXXED], POLTsym, rxn, 
                    Vl, D, ϵ, τ; sparams...)
            end
            push!(ps, p)
        end
    end
    M, N = 4, 2
    p = plot(ps...; layout = grid(M, N), 
        size = [400 * N, 300 * M])
    mysavefig(p, "dyn_vs_model_margials_$(POLTsym)"; Vl, D, τ)
end

## ----------------------------------------------------------------------------
# beta vs eps
let
    ϵs = MINDEX[:ϵs] |> sort
    colors = Plots.distinguishable_colors(length(MINDEX[:Ds]))
    colors = Dict(D => c for (D, c) in zip(MINDEX[:Ds], colors))
    p = plot(;xlabel = "beta", ylabel = "ϵ")
    sparams = (;alpha = 0.5, ms = 6)
    for (Vl, D, τ) in Iterators.product(MINDEX[[:Vls, :Ds, :τs]]...)
        ϵ_ser = []
        beta_ser = []
        for ϵ in ϵs
            MINDEX[:STATUS, Vl, D, ϵ, τ] == :death && continue
            beta = getdat([:HETER, POLTsym, :beta0], Vl, D, ϵ, τ)
            push!(ϵ_ser, ϵ)
            push!(beta_ser, beta)
        end
        scatter!(p, beta_ser, ϵ_ser; label = "", color = colors[D], sparams...)
    end
    mysavefig(p, "$(HETER)_beta_vs_eps_D_colored")
end

## ----------------------------------------------------------------------------
# let
#     for (Vl, D, ϵ, τ) = EXP_PARAMS
#         MINDEX[:STATUS, Vl, D, ϵ, τ] == :death && continue
#         dat = getdat([:DyMs], Vl, D, ϵ, τ)
#         @show length(dat)
#         break
#     end
# end

## ----------------------------------------------------------------------------
# Bound Correlation
let
    f(x) = x
    p = plot(;title = "Exchs Bounds Correlation", 
        xlabel = "dym bound", ylabel = "stst bound")
    l, u = Inf, -Inf

    STST_vgubs, DYN_vgubs = [], []
    STST_vlubs, DYN_vlubs = [], []
    for (Vl, D, ϵ, τ) in EXP_PARAMS
        MINDEX[:STATUS, Vl, D, ϵ, τ] == :death && continue

        for  MODsym in [FIXXED, HETER, HOMO]
            M = getdat([MODsym, STST_POL, :M], Vl, D, ϵ, τ)
            push!(STST_vgubs, M.net.ub[M.vg_idx])
            push!(STST_vlubs, M.net.ub[M.vl_idx])

            M = getdat([MODsym, DYN_POL, :M], Vl, D, ϵ, τ)
            push!(DYN_vgubs, M.net.ub[M.vg_idx])
            push!(DYN_vlubs, M.net.ub[M.vl_idx])
        end
    end

    xs = [DYN_vgubs; DYN_vlubs]
    ys = [STST_vgubs; STST_vlubs]
    l = minimum([l; xs; ys])            
    u = maximum([u; xs; ys])            
    plot!(p, f.([l, u]), f.([l, u]); label = "", ls = :dash, alpha = 0.8)
    scatter!(p, f.(xs), f.(ys); alpha = 0.5, color = :black, label = "")

    # saving
    mysavefig(p, "exchs_bounds_corr")

end


## ----------------------------------------------------------------------------
# Steady State EP Dynamic correlation
let
    f(x) = log10(abs(x) + 1e-8)
    
    ps = []
    for  MODsym in [FIXXED, HETER, HOMO]
        
        p = plot(;title = string(MODsym), 
            xlabel = "dym flxs", ylabel = "maxent flxs", 
            legend = :topleft, titlefont = 10, xaxisfont = 10,
            bottom_margin = 5mm, top_margin = 8mm,
            left_margin = 5mm, right_margin = 5mm, 
        )
        
        color = MOD_COLORS[MODsym]
        DYN_flxs, DYN_errs = [], []
        ME_flxs, ME_errs = [], []

        @info "Doing" MODsym STST_POL
        
        for (Vl, D, ϵ, τ) in EXP_PARAMS
            MINDEX[:STATUS, Vl, D, ϵ, τ] == :death && continue
            DyMs = getdat([:DyMs], Vl, D, ϵ, τ)
            MEMs = getdat([MODsym, STST_POL, :MEMs], Vl, D, ϵ, τ)
            
            for rxn in InLP.RXNS
                DYN_flx = InLP.av(DyMs[rxn])
                DYN_err = InLP.va(DyMs[rxn]) |> sqrt
                ME_flx = InLP.av(MEMs[rxn])
                ME_err = InLP.va(MEMs[rxn]) |> sqrt
                (isnan(DYN_flx) || isnan(ME_flx)) && continue

                push!(DYN_flxs, DYN_flx)
                push!(DYN_errs, DYN_err)
                push!(ME_flxs, ME_flx)
                push!(ME_errs, ME_err)
            end
        end
        
        xs = DYN_flxs
        ys = ME_flxs
        l = minimum(f.([xs; ys]))            
        u = maximum(f.([xs; ys]))    
        m = abs(u - l) * 0.1        
        scatter!(p, f.(xs), f.(ys); ms = 8, alpha = 0.5, color, label = "")
        plot!(p, [l - m, u + m], [l - m, u + m]; label = "", ls = :dash, alpha = 0.8)
        push!(ps, p)
    end
    M, N = 1, 3
    p = plot(ps...; layout = grid(M, N), 
        size = [400 * N, 400 * M])

    # saving
    mysavefig(p, "flxs_corr")
    
end