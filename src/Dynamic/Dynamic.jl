module Dynamic
    
    import UtilsJL
    const Ass = UtilsJL.ProjAssistant
    Ass.@gen_sub_proj
    using Plots
    import MathProgBase.HighLevelInterface: linprog
    import Clp: ClpSolver
    using ProgressMeter
    using Base.Threads
    using ExtractMacro
    using Statistics

    include("BoxGrid.jl")
    include("LP.jl")
    include("MetNets.jl")
    include("ToyModelD2.jl")
    include("ToyModelD3.jl")
    include("PlotUtils.jl")
    include("ChunkedPol.jl")
    include("Space.jl")
    include("Container.jl")
    include("utils.jl")
    include("Sim2D.jl")
    include("subspace.jl")

    function __init__()
        Ass.@create_proj_dirs
    end

end