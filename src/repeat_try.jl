#==============================================================================#
# repeat_try.jl
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
#
# e.g.
#
#   @repeat 4 try
#
#       return s3(aws, "GET", bucket, path)
#
#   catch e
#       @delay_retry if e.code in ["NoSuchBucket", "NoSuchKey"] end
#   end
#
#
# e.g.
#
#   @repeat 4 try 
#
#       return http_attempt(request)
#
#   catch e
#
#       @delay_retry if typeof(e) == UVError end
#
#       @delay_retry if http_status(e) < 200 && http_status(e) >= 500 end
#
#       @retry if http_status(e) in [301, 302, 307]
#            request.uri = URI(headers(e)["Location"])
#       end
#
#   end
#
#
# e.g.
#
#   @repeat 4 try
#
#       r = sqs(aws, Action = "CreateQueue", QueueName = name)
#       return = XML(r)[:QueueUrl]
#
#   catch e
#
#       @retry if e.code == "QueueAlreadyExists"
#           sqs_delete_queue(aws, name)
#       end
#
#       @retry if e.code == "AWS.SimpleQueueService.QueueDeletedRecently"
#           println("""Waiting 1 minute to re-create Queue "$name"...""")
#           sleep(60)
#       end
#   end
#
#
#
#------------------------------------------------------------------------------#


# Check that "expr" is "try ... catch err ... [finalise ...] end"

function check_try_catch(expr, require_exception_variable::Bool)

    @assert expr.head == :try "" *
            """Expected "try/catch" expression as argument."""

    @assert expr.args[3].head == :block 

    if require_exception_variable
        @assert typeof(expr.args[2]) == Symbol "" *
                """Expected exception vairable name."""
    else
        if typeof(expr.args[2]) != Symbol
            @assert expr.args[2] == false
            expr.args[2] = :err
        end
    end


    return (try_block, exception, catch_block) = expr.args
end


# Check that "expr" is "@macrocall if ... end".

function check_macro_if(expr)

    @assert expr.head == :macrocall &&
            length(expr.args) == 2 &&
            typeof(expr.args[2]) == Expr &&
            expr.args[2].head == :if "" *
            """$(expr.args[1]) expects "if" expression as argument."""

    if_expr = expr.args[2]

    @assert length(if_expr.args) == 2 &&
            if_expr.args[2].head == :block "" *
            """"else" not allowed in $(expr.args[1]) expression."""

    return if_expr
end


function esc_args!(expr::Expr)
    for (i, arg) in enumerate(expr.args)
        expr.args[i] = esc(arg)
    end
end


function might_return(expr)
    isa(expr, Expr) && (expr.head == :return ||
                        any(might_return, expr.args))
end


macro repeat(max, try_expr::Expr)

    # Extract exception variable and catch block from "try" expression...
    (try_block, exception, catch_block) = check_try_catch(try_expr, false)

    # Escape everything except catch block...
    esc_args!(try_expr)
    try_expr.args[3] = catch_block

    # Rethrow at end of catch block...
    push!(catch_block.args, :($exception == nothing || rethrow($exception)))

    for (i, expr) in enumerate(catch_block.args)

        # Look for "@ignore/@retry if..." expressions in catch block...
        if (typeof(expr) == Expr
        &&  expr.head == :macrocall
        &&  expr.args[1] in [Symbol("@retry"),
                             Symbol("@delay_retry"),
                             Symbol("@ignore")])

            handler = string(expr.args[1])

            if_expr = check_macro_if(expr)
            (condition, action) = if_expr.args
            if_expr.args[1] = :(try $(esc(condition)) catch e false end)

            # Clear exception variable at end of "@ignore if..." block...
            if handler == "@ignore"
                push!(action.args, :($exception = nothing))
            end

            esc_args!(action)

            # Loop to try again at end of "@retry if..." block...
            if handler == "@retry"
                push!(action.args, :(if i < $(esc(max)) continue end))
            end

            # Add exponentially increasing delay with random jitter,
            # and loop to try again at end of "@delay_retry if..." block...
            if handler == "@delay_retry"
                push!(action.args, quote
                    if i < $(esc(max))
                        sleep(delay * (0.8 + (0.4 * rand())))
                        delay *= 10
                        continue
                    end
                end)
            end

            # Replace @ignore/@retry macro call with modified if expression...
            catch_block.args[i] = if_expr
        else
            catch_block.args[i] = esc(expr)
        end
    end

    # Build retry expression...
    # FIXME might_return() test should not be needed when this is fixed:
    # https://github.com/JuliaLang/julia/issues/11169
    if might_return(try_expr)
        quote
            delay = 0.05

            for i in 1:$(esc(max))
                $try_expr
                break
            end
        end
    else
        quote
            delay = 0.05
            result = false

            for i in 1:$(esc(max))
                result = $try_expr
                break
            end

            result
        end
    end
end



#==============================================================================#
# End of file.
#==============================================================================#
