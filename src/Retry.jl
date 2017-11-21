module Retry

__precompile__(true)

export @repeat, @protected, efield, ecode

efield(x, f, default=nothing) = f in fieldnames(x) ? getfield(x, f) : default
ecode(x) = efield(x, :code)

include("repeat_try.jl")
include("protected_try.jl")

end # module
