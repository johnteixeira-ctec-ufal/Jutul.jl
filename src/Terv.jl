module Terv

using SparseArrays
using LinearAlgebra
using BenchmarkTools
using ForwardDiff
using KernelAbstractions, CUDA, CUDAKernels

# MRST stuff
include("mrst_input.jl")
# Meat and potatoes
include("static_structures.jl")
include("assembly.jl")
include("benchmarks.jl")

end # module
