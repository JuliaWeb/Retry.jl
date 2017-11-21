#==============================================================================#
# protected_try.jl
#
# "@protected try" and @ignore exception handling
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
#       s3(aws, "PUT", bucket)
#
#    catch e
#       @ignore if e.code == "BucketAlreadyOwnedByYou" end
#    end
#
# becomes...
#
#    try
#
#        s3(aws, "PUT", bucket)
#
#    catch e
#        try
#            if e.code == "BucketAlreadyOwnedByYou"
#                e = nothing
#            end
#        end
#        e == nothing || rethrow(e)
#    end
# 
#
#-------------------------------------------------------------------------------


macro protected(try_expr::Expr)

    # Extract exception variable and catch block from "try" expression...
    (try_block, exception, catch_block) = check_try_catch(try_expr, true)

    for (i, expr) in enumerate(catch_block.args)

        # Look for "@ignore if..." expressions in catch block...
        if (typeof(expr) == Expr
        &&  expr.head == :macrocall
        &&  expr.args[1] == Symbol("@ignore"))

            if_expr = check_macro_if(expr)
            (condition, action) = if_expr.args

            # Clear exception variable at end of "@ignore if..." block...
            push!(action.args, :($exception = nothing))
            
            # Replace "@ignore if...", with "if..."...
            catch_block.args[i] = if_expr
        end
    end

    # Check for nothing exception at start of catch block...
    unshift!(catch_block.args, :($exception == nothing && rethrow($exception)))

    # Check rethrow flag at end of catch block...
    push!(catch_block.args,  :($exception == nothing || rethrow($exception)))

    return esc(try_expr)
end



#==============================================================================#
# End of file.
#==============================================================================#
