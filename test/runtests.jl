using Chemostat_Dynamics
using Chemostat_Dynamics.Utilities
using Chemostat_Dynamics.Polytopes
using Chemostat_Dynamics.MonteCarlo
using Chemostat_Dynamics.MaxEnt
using Test

@testset "Chemostat_Dynamics.jl" begin
    # Write your tests here.

    ## ------------------------------------------------------------------
    @testset "Polytope" begin
        p = Polytope() # Default params
        # The polytope is pointy in this regions
        @test Δvg(vatp_global_max(p), p) == 0.0
        @test Δvg(vatp_global_min(p), p) == 0.0
        @test Δvatp(vg_global_min(p), p) == 0.0

        # The polytope is NOT pointy in this regions_
        @test Δvatp(vg_global_max(p), p) > 0.0
    end

    ## ------------------------------------------------------------------
    @testset "Monte Carlos" begin
        n = Int(5e6)
        p = Polytope() # Default params
        cells_pool = generate_random_cells(p, n; tries = 100, verbose = true)
        @test all(is_inpolytope.(cells_pool))
        @test all(map((cp) -> cp === p, getfield.(cells_pool, :p)))

        mvatp = vatp_global_max(p)
        pcells = pick_cells(n, cells_pool) do cell
            prob = vatp(cell)/mvatp
            return rand() <= prob
        end
        @test all(is_inpolytope.(pcells))
        @test all(map((cp) -> cp === p, getfield.(pcells, :p)))
        @test sum(vatp.(cells_pool)) < sum(vatp.(pcells)) # See picking function
    end

    ## ------------------------------------------------------------------
    @testset "Utilities" begin
        @testset "Get chunck " begin
            for it in 1:100
                r = 1:rand(50:100)
                n = rand(3:5)
                chuncks = get_chuncks(r, n; th = 0)
                @test all(vcat(chuncks...) .== collect(r))
            end
        end
    end

    ## ------------------------------------------------------------------
    @testset "MaxEnt" begin
        @testset "vatp_marginal " begin
            for it in 1:100
                xi = rand()*1e3 + 3e-2
                pol = Polytope(;xi)
                beta = rand()*1e3 + 1e-3
                rvatp, probs = vatp_marginal(pol, beta; n = Int(1e5))
                @test length(rvatp) == length(probs)
                @test isapprox(sum(probs), 1.0; atol = 1e-7)
            end
        end
    end
end


