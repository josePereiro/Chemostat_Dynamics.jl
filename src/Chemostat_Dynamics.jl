module Chemostat_Dynamics

export PROJECT_NAME, PROJECT_DIR, FIGURES_DIR, DATA_DIR

include("Meta/Meta.jl")
include("Utilities/Utilities.jl")
include("Polytopes/Polytopes.jl")
include("MonteCarlo/MonteCarlo.jl")
include("MaxEnt/MaxEnt.jl")

function __init__()
    _create_dirs()
end

end
