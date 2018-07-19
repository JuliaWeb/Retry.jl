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

function check_try_catch(expr::Expr, require_exception_variable::Bool)
    if expr.head !== :try
        throw(ArgumentError("Expected a `try`/`catch` expression argument"))
    end
    if require_exception_variable
        expr.args[2] isa Symbol || throw(ArgumentError("Expected exception variable name"))
    else
        if !isa(expr.args[2], Symbol)
            @assert expr.args[2] == false
            expr.args[2] = :err
        end
    end
    return (expr.args...,)
end


# Check that "expr" is "@macrocall if ... end".

function check_macro_if(expr::Expr)
    if !(expr.head == :macrocall && length(expr.args) == 3)
        throw(ArgumentError("Expected macro call with a single expression argument"))
    end
    (macroname::Symbol, lineinfo::LineNumberNode, ifexpr::Expr) = expr.args
    if ifexpr.head !== :if
        throw(ArgumentError("$macroname: expecting an `if` expression"))
    end
    if !(length(ifexpr.args) == 2 && ifexpr.args[2].head == :block)
        throw(ArgumentError("$macroname: `else` expression is not allowed"))
    end
    return ifexpr
end


function esc_args!(expr::Expr)
    for (i, arg) in enumerate(expr.args)
        if isa(arg, Symbol) || !isa(arg, LineNumberNode)
            expr.args[i] = esc(arg)
        end
    end
end


macro repeat(max, try_expr::Expr)

    # Extract exception variable and catch block from "try" expression...
    (try_block, exception, catch_block) = check_try_catch(try_expr, false)

    # Escape everything except catch block...
    esc_args!(try_expr)
    try_expr.args[3] = catch_block

    max = esc(max)
    exception = esc(exception)

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
            if_expr.args[1] = esc(condition)
            esc_args!(action)

            # Clear exception variable at end of "@ignore if..." block...
            if handler == "@ignore"
                push!(action.args, :(ignore = true))
            end

            # Loop to try again at end of "@retry if..." block...
            if handler == "@retry"
                push!(action.args, :(if i < $max continue end))
            end

            # Add exponentially increasing delay with random jitter,
            # and loop to try again at end of "@delay_retry if..." block...
            if handler == "@delay_retry"
                push!(action.args, quote
                    if i < $max
                        sleep(delay * (0.8 + (0.4 * rand())))
                        delay *= 10
                        continue
                    end
                end)
            end

            # Replace @ignore/@retry macro call with modified if expression...
            catch_block.args[i] = if_expr
        elseif !isa(expr, LineNumberNode)
            catch_block.args[i] = esc(expr)
        end
    end

    # Check for nothing exception at start of catch block...
    insert!(catch_block.args, 2, :($exception == nothing && rethrow()))
    pushfirst!(catch_block.args, :(ignore = false))

    # Rethrow at end of catch block...
    push!(catch_block.args, :(ignore || rethrow($exception)))

    # Build retry expression...
    quote
        delay = 0.05
        result = false

        for i in 1:$max
            result = $try_expr
            break
        end

        result
    end
end


#==============================================================================#
# End of file.
#==============================================================================#
