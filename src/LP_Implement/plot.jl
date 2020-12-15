## ---------------------------------------------------------
function plot_res(M::SimModel, ts::ResTS; f = (x) -> x)
    p1 = plot(xlabel = "time", ylabel = "conc")
    plot!(p1, f.(ts.sg_ts); label = "sg", lw = 3)
    plot!(p1, f.(ts.sl_ts); label = "sl", lw = 3)
    
    p2 = plot(xlabel = "time", ylabel = "X")
    plot!(p2, f.(ts.X_ts); label = "X", lw = 3)

    p3 = plot(xlabel = "time", ylabel = "D")
    plot!(p3, f.(ts.D_ts); label = "D", lw = 3)

    p4 = plot_politope(M)
    
    p = plot([p1, p2, p3, p4]...;
        size = [800, 700], layout = 4)
end

function plot_politope(M::SimModel; 
        D = 250.0,
        N = 1000
    )
    
    vatp_range, vg_ranges = vatpvg_ranges(M)
    # i_vatp_range = collect(enumerate(vatp_range))
    # vatpL, vatpU = minimum(vatp_range), maximum(vatp_range)
    vgL, vgU = minimum(first.(vg_ranges)), maximum(last.(vg_ranges))
    Δvg = step(first(vg_ranges))
    vg_range = vgL:Δvg:vgU
    # V = (vatpU - vatpL) * (vgU - vgL)
    # N = floor(Int, D * V)
    mX, MX = lXgamma(M)

    p = plot(xlabel = "vatp", ylabel = "vg")
    c = 0
    # for i in 1:N
    while c < N
        # vatpi, vatp = rand(i_vatp_range)
        vatp = rand(vatp_range)
        vg = rand(vg_range)
        !haskey(M.Xb, vatp) && continue
        !haskey(M.Xb[vatp], vg) && continue

        lX = M.Xb[vatp][vg]
        color = :black
        ms = 10.0 * lX/MX
        scatter!(p, [vatp], [vg]; color, label = "", ms, alpha = 0.4)
        c += 1
    end
    p
end