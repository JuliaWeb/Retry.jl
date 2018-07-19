__precompile__(true)

module Retry

export @repeat, @protected, efield, ecode

efield(x, f, default=nothing) = f in fieldnames(typeof(x)) ? getfield(x, f) : default
ecode(x) = efield(x, :code)

include("repeat_try.jl")
include("protected_try.jl")

end # module
