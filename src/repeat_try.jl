#==============================================================================#
# retry.jl
#
# Copyright Sam O'Connor 2014 - All rights reserved
#==============================================================================#


#------------------------------------------------------------------------------#
#
# @repeat try... re-writes "try_expr" to try again at most "max" times and to
# automatically rethrow() at end of "catch" block (unless exception has been
# set to nothing). 
#
# @ignore if... re-writes "if..." to ignore exceptions thrown by the if
# "condition" and to set "exception" = nothing if the "condition" is true
# (to prevent automatic rethrow).
#
# @retry if... re-writes "if..." to ignore exceptions thrown by the if
# "condition" and to try again if the "condition" is true.
#
# @delay_retry if... adds exponentially increasing delay with random jitter... 
#
# e.g.
#
#    @repeat 4 try 
#
#        http_get(url)
#
#    catch e
#        @retry if isa(e, UVError) end
#        @ignore if e.http_code == "203"
#    end
#
#------------------------------------------------------------------------------#


macro repeat(max::Integer, try_expr::Expr)

    @assert try_expr.head == :try "" *
            """@repeat expects "try/catch" expression as 2nd argument."""

    @assert try_expr.args[3].head == :block &&
            isa(try_expr.args[2], Symbol) "" *
            """"@repeat n try" expects "catch" block with exception variable."""

    # Extract exception variable and catch block from "try" expression...
    (try_block, exception, catch_block) = try_expr.args

    # Look for "@ignore/@retry if..." expressions in catch block...
    for (i, expr) in enumerate(catch_block.args)

        if (isa(expr, Expr)
        &&  expr.head == :macrocall
        &&  expr.args[1] in [Symbol("@retry"),
                             Symbol("@delay_retry"),
                             Symbol("@ignore")])

            # Check for "if" after macro call...
            @assert length(expr.args) == 2 &&
                    isa(expr.args[2], Expr) &&
                    expr.args[2].head == :if "" *
                    """$(expr.args[1]) expects "if" expression as argument."""

            if_expr = expr.args[2]

            @assert length(if_expr.args) == 2 &&
                    if_expr.args[2].head == :block "" *
                    """"else" not allowed in $(expr.args[1]) expression."""

            # Clear exception variable at end of "@ignore if..." block...
            if expr.args[1] == Symbol("@ignore")
                push!(if_expr.args[2].args, :($exception = nothing))
            end

            # Loop to try again at end of "@retry if..." block...
            if expr.args[1] == Symbol("@retry")
                push!(if_expr.args[2].args, :(continue))
            end

            # Loop to try again at end of "@delay_retry if..." block...
            if expr.args[1] == Symbol("@delay_retry")
                push!(if_expr.args[2].args, quote

                    # Exponentially increasing delay with random jitter... 
                    sleep(delay * (0.8 + (0.4 * rand())))
                    delay *= 10
                    continue
                end)
            end

            # Replace @ignore/@retry macro call with modified if expression...
            catch_block.args[i] = :(try $if_expr end)
        end
    end

    # Don't apply catch rules on last attempt...
    unshift!(catch_block.args,  :(i < $max || break))

    # Check rethrow flag at end of catch block...
    push!(catch_block.args,  :($exception == nothing || rethrow($exception)))


    # Build retry expression...
    retry_expr = quote

        delay = 0.05

        for i in 1:$max
            $try_expr
            break
        end
    end
end



#==============================================================================#
# End of file.
#==============================================================================#
