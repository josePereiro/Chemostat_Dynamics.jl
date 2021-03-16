module Dynamic

    using ..Chemostat_InSilico
    const InCh = Chemostat_InSilico
    import MathProgBase.HighLevelInterface: linprog
    import Clp: ClpSolver
    import ProgressMeter: Progress, update!, next!, finish!
    import Serialization: serialize, deserialize
    using Plots
    import GR
    GR.inline("png")
    using Base.Threads
    using Random
    import FileIO
    import JuMP
    import GLPK
    import UtilsJL
    const UJL = UtilsJL
    UJL.gen_sub_proj(@__MODULE__)

    include("LP.jl")
    include("MetNets.jl")
    include("SimModel.jl")
    include("ResTS.jl")
    include("range.jl")
    include("plot.jl")
    include("cache.jl")
    include("board_utils.jl")
    include("run_simulation_fPx.jl")
    include("run_simulation_fX.jl")
    include("run_simulation_vg.jl")
    include("marginals.jl")
    include("idxdat.jl")
    include("mysavefig.jl")
    include("pos_defined.jl")
    include("yLP.jl")
    include("join.jl")

    function __init__()
        UJL.create_proj_dirs(@__MODULE__)
    end

end