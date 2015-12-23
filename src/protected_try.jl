#==============================================================================#
# trap.jl
#
# "@protected try" and @trap exception handling
#
# Copyright Sam O'Connor 2014 - All rights reserved
#==============================================================================#


#-------------------------------------------------------------------------------
#
# @protected try... re-writes "try_expr" to automatically rethrow()
# at end of "catch" block (unless exception has been set to nothing).
#
# @ignore if... re-writes "if..." to ignore exceptions thrown by the if
# "condition" and to set "exception" = nothing if the "condition" is true
# (to prevent automatic rethrow).
#
# Exceptions raised by the "if" condition in "@ignore if" are ignored.
# i.e. "@ignore if err.code == "404" is safe even if "err" has no "code" field.
#
# e.g.
#    
#    @protected try
#
#        return s3_get(url)
#
#    catch e
#        @ignore if e.code in {"NoSuchKey", "AccessDenied"}
#            return nothing
#        end
#    end
#
#-------------------------------------------------------------------------------


macro protected(try_expr::Expr)

    @assert try_expr.head == :try "" *
            """@protected expects "try/catch" expression as argument."""

    @assert try_expr.args[3].head == :block &&
            isa(try_expr.args[2], Symbol) "" *
            """@protected try expects "catch" block with exception variable."""

    # Extract exception variable and catch block from "try" expression...
    (try_block, exception, catch_block) = try_expr.args

    # Look for "@ignore if..." expressions in catch block...
    for (i, expr) in enumerate(catch_block.args)

        if (isa(expr, Expr)
        &&  expr.head == :macrocall
        &&  expr.args[1] == Symbol("@ignore"))

            # Check for "if" after "@ignore"...
            @assert length(expr.args) == 2 &&
                    isa(expr.args[2], Expr) &&
                    expr.args[2].head == :if "" *
                    """@ignore expects "if" expression as argument."""

            if_expr = expr.args[2]

            @assert length(if_expr.args) == 2 &&
                    if_expr.args[2].head == :block "" *
                    """"else" not allowed in @ignore expression."""

            # Clear exception variable at end of "@ignore if..." block...
            push!(if_expr.args[2].args, :($exception = nothing))
            
            # Replace "@ignore if...", with "try if..."...
            catch_block.args[i] = :(try $if_expr end)
        end
    end

    # Check rethrow flag at end of catch block...
    push!(catch_block.args,  :($exception == nothing || rethrow($exception)))

    return try_expr
end



#==============================================================================#
# End of file.
#==============================================================================#
