import DrWatson: quickactivate
quickactivate(@__DIR__, "Chemostat_InSilico")

@time begin
    import Chemostat_InSilico
    const InCh = Chemostat_InSilico
    const InLP = InCh.LP_Implement

    import UtilsJL
    const UJL = UtilsJL
    using Base.Threads
    using Dates
    using Serialization
    using Random
end

## ----------------------------------------------------------------------------
# Load and clear DAT
# DINDEX [Vl, D, ϵ, τ] 
DINDEX = UJL.load_data(InCh.DYN_DATA_INDEX_FILE) # Dynamic index
DATA_FILE_PREFFIX = "marginal_dat"
dat_file(;sim_params...) = joinpath(
    InCh.DYN_DATA_DIR, 
    InLP.mysavename(DATA_FILE_PREFFIX, "jls"; sim_params...)
)
idxdat(dk, indexks...; cache = false, emptycache = true) = 
    InLP.idxdat(DINDEX, dk, indexks...; cache, emptycache)

# ----------------------------------------------------------------------------
const WLOCK = ReentrantLock()

# ----------------------------------------------------------------------------
# METHOD VARIANTS
const ME_Z_OPEN_G_OPEN          = :ME_Z_OPEN_G_OPEN           # Do not use extra constraints
const ME_Z_OPEN_G_BOUNDED       = :ME_Z_OPEN_G_BOUNDED        # 
const ME_Z_EXPECTED_G_OPEN      = :ME_Z_EXPECTED_G_OPEN       # Match ME and Dy biom average
const ME_Z_EXPECTED_G_EXPECTED  = :ME_Z_EXPECTED_G_EXPECTED   # 
const ME_Z_EXPECTED_G_BOUNDED   = :ME_Z_EXPECTED_G_BOUNDED    # Match ME and Dy biom average and constraint av_ug
const ME_Z_FIXXED_G_OPEN        = :ME_Z_FIXXED_G_OPEN         # Fix biom around observed
const ME_Z_FIXXED_G_BOUNDED     = :ME_Z_FIXXED_G_BOUNDED      # Fix biom around observed

const FBA_Z_OPEN_G_OPEN       = :FBA_Z_OPEN_G_OPEN
const FBA_Z_OPEN_G_BOUNDED    = :FBA_Z_OPEN_G_BOUNDED
const FBA_Z_FIXXED_G_OPEN     = :FBA_Z_FIXXED_G_OPEN 
const FBA_Z_FIXXED_G_BOUNDED  = :FBA_Z_FIXXED_G_BOUNDED


## ----------------------------------------------------------------------------
function run_ME!(M, MEmode; LP_cache, δ, δμ, biom_avPX, vg_avPX)
    
    # biomass rate
    biom_idx = M.obj_idx
    z(vatp, vg) = LP_cache[vatp][vg][biom_idx]
    
    # G BOUNDING
    if MEmode == ME_Z_OPEN_G_BOUNDED ||
            MEmode == ME_Z_EXPECTED_G_BOUNDED ||
            MEmode == ME_Z_FIXXED_G_BOUNDED
        # Fix av_ug
        net = M.net
        net.ub[M.vg_idx] = min(M.Vg, M.cg * M.D/ M.X)
        net.ub[M.vl_idx] = min(M.Vl, M.cl * M.D/ M.X)
        L, U = InLP.fva(net)
        net.lb .= L; net.ub .= U
    end

    beta_biom = 0.0
    beta_vg = 0.0

    # EXPECTED
    if MEmode == ME_Z_EXPECTED_G_OPEN || 
            MEmode == ME_Z_EXPECTED_G_BOUNDED
        verb_frec = 50

        # Gradient descent
        target = biom_avPX
        x0 = 1.5e2
        x1 = x0 * 0.9
        maxΔ = 100.0
        th = 1e-3
        maxiters = 500
        it = 1

        # grad desc
        join = InLP.get_join(M)
        function f1(beta_biom)

            PME = InLP.get_join!(M, join) do vatp, vg
                exp(beta_biom * z(vatp, vg))
            end
            biom_avPME = InLP.ave_over(PME) do vatp, vg
                z(vatp, vg)
            end
            
            err = abs(biom_avPX - biom_avPME)/biom_avPX
            show_info = it == 1 || rem(it, verb_frec) == 0 || 
                it == maxiters || err < th
            show_info && lock(WLOCK) do
                thid = threadid()
                @info("Grad Descent ", 
                    it, MEmode, 
                    (biom_avPX, biom_avPME), 
                    err, beta_biom, thid
                ); println()
            end

            it += 1
            return biom_avPME
        end

        beta_biom = UJL.grad_desc(f1; th, 
            target, x0, x1, maxΔ, maxiters, 
            verbose = false
        )

    end

    if MEmode == ME_Z_EXPECTED_G_EXPECTED

        verb_frec = 50

        target = [biom_avPX, vg_avPX]
        x0 = [100.0, -10.0]
        x1 = [101.0, -11.0]
        maxΔ = [80.0, 30.0]
        maxiters = 500
        th = 1e-3
        it = 1

        join = InLP.get_join(M)
        function f2(betas)
            biom_beta, vg_beta = betas
            PME = InLP.get_join!(M, join) do vatp, vg
                v = [z(vatp, vg), vg]
                exp(betas' * v)
            end
            biom_avPME = InLP.ave_over(PME) do vatp, vg
                z(vatp, vg)
            end
            vg_avPME = InLP.ave_over(PME) do vatp, vg
                vg
            end
            
            biom_err = abs(biom_avPX - biom_avPME)/biom_avPX
            vg_err = abs(vg_avPX - vg_avPME)/vg_avPX
            err = max(biom_err, vg_err)
            show_info = it == 1 || rem(it, verb_frec) == 0 || 
                it == maxiters || err < th
            show_info && lock(WLOCK) do
                thid = threadid()
                @info("Grad Descent ", 
                    it, MEmode, 
                    (biom_avPX, biom_avPME),
                    (vg_avPX, vg_avPME),
                    err, biom_beta, vg_beta, 
                    thid
                ); println()
            end

            it += 1
            return [biom_avPME, vg_avPME]
        end

        beta_biom, beta_vg = UJL.grad_desc_vec(f2; 
            target, x0, x1, maxΔ, th, maxiters, 
            verbose = false
        )
    end

    # Z FIXXED
    if MEmode == ME_Z_FIXXED_G_OPEN || 
            MEmode == ME_Z_FIXXED_G_BOUNDED
        # Fix biomass to observable
        net = M.net
        net.ub[M.obj_idx] = biom_avPX * (1.0 + δμ)
        net.lb[M.obj_idx] = biom_avPX * (1.0 - δμ)
        L, U = InLP.fva(net)
        net.lb .= L; net.ub .= U
    end

    MEMs = InLP.get_marginals(M; δ, LP_cache, verbose = false) do vatp, vg
        exp((beta_biom * z(vatp, vg)) + (beta_vg * vg))
    end
    return MEMs, beta_biom, beta_vg
end

## ----------------------------------------------------------------------------
function run_FBA!(M, FBAmode; LP_cache, δ, δμ, biom_avPX, verbose = true)

    # Z FIXXED
    if FBAmode == FBA_Z_FIXXED_G_OPEN || 
            FBAmode == FBA_Z_FIXXED_G_BOUNDED
        # Fix biomass to observable
        net = M.net
        net.ub[M.obj_idx] = biom_avPX * (1.0 + δμ)
        net.lb[M.obj_idx] = biom_avPX * (1.0 - δμ)
        L, U = InLP.fva(net)
        net.lb .= L; net.ub .= U
    end

    # G BOUNDING
    if FBAmode == FBA_Z_OPEN_G_BOUNDED ||
            FBAmode == FBA_Z_FIXXED_G_BOUNDED
        # Fix av_ug
        net = M.net
        net.ub[M.vg_idx] = min(M.Vg, M.cg * M.D/ M.X)
        net.ub[M.vl_idx] = min(M.Vl, M.cl * M.D/ M.X)
        L, U = InLP.fva(net)
        net.lb .= L; net.ub .= U
    end

    # FBA
    # Find maximum feasible vatp
    vatp_range, vg_ranges = InLP.vatpvg_ranges(M)
    max_vatp = -Inf
    min_vg = Inf
    # (max_vatp, min_vg) will maximize the yield
    for (vatpi, vatp) in vatp_range |> enumerate
        vg_range = vg_ranges[vatpi]
        isempty(vg_range) && continue
        if vatp > max_vatp
            max_vatp = vatp
            min_vg = minimum(vg_range)
        end
    end
    @assert !isinf(max_vatp)

    fbaf(vatp, vg) = (vatp == max_vatp && vg == min_vg) ? 1.0 : 0.0
    FBAMs = InLP.get_marginals(fbaf, M; δ, LP_cache, verbose)
    return FBAMs
end

## ----------------------------------------------------------------------------
# TODO: make script args
REDO_MAXENT = false
REDO_FBA = false

## ----------------------------------------------------------------------------
# COMPUTE MARGINALS
INDEX = UJL.DictTree() # marginals dat
let
    δ = INDEX[:δ]   = 0.08 # marginal discretization factor
    δμ = INDEX[:δμ] = 0.01 # ME_Z_FIXXED_G_OPEN biomass variance
    gc = 0

    INDEX[:Vls], INDEX[:Ds] = [], []
    INDEX[:ϵs], INDEX[:τs] = [], []
    
    Vls, Ds, ϵs, τs = DINDEX[[:Vls, :Ds, :ϵs, :τs]]
    
    params = Iterators.product(Vls, Ds, ϵs, τs)
    Ch = Channel(1) do Ch_
        for (Vl, D, ϵ, τ) in params
            put!(Ch_, (Vl, D, ϵ, τ))
        end
    end
    N = length(params)
    
    LP_cache = nothing
    @threads for thid in 1:nthreads()
        for (Vl, D, ϵ, τ) in Ch
            cfile = dat_file(;Vl, D, ϵ, τ, δ, δμ)
            
            ## ----------------------------------------------------------------------------
            MDAT = UJL.DictTree()
            M0 = MDAT[:M0] = idxdat([:M], Vl, D, ϵ, τ; cache = true)
            status = idxdat([:status], Vl, D, ϵ, τ; cache = false, emptycache = true)
            
            # LP_cache = nothing
            c = nothing
            lock(WLOCK) do
                gc += 1; c = gc
                
                # LP_cache = InLP.vgvatp_cache(M0)
                isnothing(LP_cache) && (LP_cache = InLP.vgvatp_cache(M0))

                push!(INDEX[:Vls], Vl); push!(INDEX[:Ds], D)
                push!(INDEX[:ϵs], ϵ); push!(INDEX[:τs], τ)
                INDEX[:DFILE, Vl, D, ϵ, τ] = relpath(cfile, InCh.PROJECT_DIR)
                INDEX[:STATUS, Vl, D, ϵ, τ] = status
                @info("Doing $c, prog: $gc/$N ... ", 
                    (Vl, D, ϵ, τ), 
                    M0.X, status, 
                    thid
                ); println()
            end
            
            ## ----------------------------------------------------------------------------
            if status != :stst # Only accept steady states
                lock(WLOCK) do
                    @info("Not a Stst (Skipping) $c, prog: $gc/$N ... ",
                        (Vl, D, ϵ, τ),
                        M0.X, status,
                        thid
                    ); println()
                end
                continue 
            end

            ## ----------------------------------------------------------------------------
            if isfile(cfile) # Check caches
                if REDO_MAXENT || REDO_FBA
                    MDAT = deserialize(cfile)
                    lock(WLOCK) do
                        @info("Cache found (Redoing) $c, prog: $gc/$N ... ", 
                            (Vl, D, ϵ, τ), 
                            status, basename(cfile),
                            REDO_MAXENT, REDO_FBA,
                            thid
                        ); println()
                    end
                else
                    lock(WLOCK) do
                        @info("Cache found (Skipping) $c, prog: $gc/$N ... ", 
                            (Vl, D, ϵ, τ), 
                            status, basename(cfile),
                            thid
                        ); println()
                    end
                    continue # skip
                end
            end
            
            ## ----------------------------------------------------------------------------
            # Dynamic marginal
            fX(vatp, vg) = M0.Xb[vatp][vg] / M0.X
            DyMs = InLP.get_marginals(fX, M0; δ, LP_cache, verbose = false)
            biom_avPX = InLP.av(DyMs[InLP.BIOMASS_IDER]) # biomass dynamic mean
            vg_avPX = InLP.av(DyMs["gt"]) # biomass dynamic mean
            lock(WLOCK) do
                MDAT[:DyMs] = DyMs
            end
            DyMs = nothing

            ## ----------------------------------------------------------------------------  
            # MaxEnt marginals
            for MEmode in [ 
                    ME_Z_OPEN_G_OPEN, ME_Z_OPEN_G_BOUNDED, 
                    ME_Z_EXPECTED_G_OPEN, ME_Z_EXPECTED_G_BOUNDED,
                    ME_Z_FIXXED_G_OPEN, ME_Z_FIXXED_G_BOUNDED, 
                    ME_Z_EXPECTED_G_EXPECTED
                ]

                isfile(cfile) && !REDO_MAXENT && break

                    # Setup network
                    M = deepcopy(M0)
                    
                    MEMs, beta_biom, beta_vg = run_ME!(M, MEmode; 
                        LP_cache, δ, δμ, 
                        biom_avPX, vg_avPX
                    )
                    biom_avPME = InLP.av(MEMs[InLP.BIOMASS_IDER]) # biomass dynamic mean
                    vg_avPME = InLP.av(MEMs["gt"]) # biomass dynamic mean

                    # Ranges
                    vatp_range, vg_ranges = InLP.vatpvg_ranges(M)

                    lock(WLOCK) do
                        MDAT[MEmode, :M] = M
                        MDAT[MEmode, :Ms] = MEMs
                        MDAT[MEmode, :beta_biom] = beta_biom
                        MDAT[MEmode, :beta_vg] = beta_vg
                        MDAT[MEmode, :POL] = (;vatp_range, vg_ranges)

                        @info("Done MaxEnt  $c, prog: $gc/$N ... ",
                            MEmode,  
                            (Vl, D, ϵ, τ),
                            M0.X, 
                            (biom_avPX, biom_avPME),
                            (vg_avPX, vg_avPME),
                            thid
                        ); println()
                    end
            end # for MEmode

            ## ----------------------------------------------------------------------------
            # FBA
            for FBAmode in [
                    FBA_Z_OPEN_G_OPEN, FBA_Z_OPEN_G_BOUNDED,
                    FBA_Z_FIXXED_G_OPEN, FBA_Z_FIXXED_G_BOUNDED
                ]
                
                isfile(cfile) && !REDO_FBA && break

                    # Setup network
                    M = deepcopy(M0)
                    
                    FBAMs = run_FBA!(M, FBAmode; 
                        LP_cache, δ, δμ, biom_avPX, verbose = false)
                    biom_avFBA = InLP.av(FBAMs[InLP.BIOMASS_IDER]) # biomass dynamic mean

                    # Ranges
                    vatp_range, vg_ranges = InLP.vatpvg_ranges(M)

                    lock(WLOCK) do
                        MDAT[FBAmode, :M] = M
                        MDAT[FBAmode, :Ms] = FBAMs
                        MDAT[FBAmode, :POL] = (;vatp_range, vg_ranges)

                        @info("Done FBA  $c, prog: $gc/$N ... ",
                        FBAmode,  
                            (Vl, D, ϵ, τ),
                            M0.X, 
                            (biom_avPX, biom_avFBA),
                            thid
                        ); println()
                    end
            end

            ## ----------------------------------------------------------------------------
            # SAVING
            lock(WLOCK) do
                @info("Finished  $c, prog: $gc/$N ... ",
                    (Vl, D, ϵ, τ),
                    M0.X, basename(cfile),
                    thid
                ); println()
                serialize(cfile, MDAT) 
            end
            GC.gc()
        end # for (Vl, D, ϵ, τ) in Ch
    end #  @threads

    sort!(unique!(INDEX[:Vls])); sort!(unique!(INDEX[:Ds]))
    sort!(unique!(INDEX[:ϵs])); sort!(unique!(INDEX[:τs]))
end

## ----------------------------------------------------------------------------
# SAVING
UJL.save_data(InCh.MARGINALS_INDEX_FILE, INDEX)


