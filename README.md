# Retry

Macros for simplified exception handling.

`@repeat try`, `@retry`, `@delay_retry`, `@protected try`, `@ignore`.

[![Build Status](https://travis-ci.org/JuliaWeb/Retry.jl.svg)](https://travis-ci.org/JuliaWeb/Retry.jl)

## Exception Handling In Julia

Julia's `try/catch` statement catches all exceptions regardless of type
or error code.

The [examples in the Julia manual](http://docs.julialang.org/en/latest/manual/control-flow/#the-try-catch-statement)
involve mathematical errors that occur in the immediate context of
the `try` block. The examples assume that there is no possibility
of unexpected exceptions and hence no need to `rethrow()`. For
many technical computing tasks this is probably reasonable.

However, typical systems-programming tasks must deal with with
multi-layered distributed service stacks, interfaces to external
systems and resource contention. These problems demand fine-grained
exception filtering, simple expression of retry loops and confidence
that unexpected exceptions are not unintentionally caught and ignored.

Julia's `catch` block can include conditional logic to take appropriate
action according to error type/code; and to rethrow exceptions that
are not handled. However, this approach can seem cumbersome in
comparison to the richer exception handling mechanisms provided in
some systems programming languages. A simple careless omission of
`retrhow()` at the end of a catch block causes all exceptions to
be ignored resulting in behaviour that can be very hard to debug.

## `@protected try`

The `@protected try` macro extends `try/catch` to:

 * automatically insert `rethow()` at the end of the `catch` block, and
 * provide an unambiguous syntax for handling specific errors.

Consider the following call to Create an authentication profile for an
AWS EC2 virtual machine.

```julia
try 

    iam(aws, Action = "CreateInstanceProfile", InstanceProfileName = name)

catch e
    if !(typeof(e) == AWSException && e.code == "EntityAlreadyExists")
        rethrow(e)
    end
end
```

`@protected try` allows this to be simplified to:


```julia
@protected try 

    iam(aws, Action = "CreateInstanceProfile", InstanceProfileName = name)

catch e
    @ignore if e.code == "EntityAlreadyExists" end
end
```

Note that the `@ignore if` statement does not check `typeof(e)` before
accessing `e.code`. The `@ignore if` condition is wrapped in an inner
`try/catch` block such that any exceptions thrown by the condition are
treated the same as the condition being `false`. The code generated
by `@protected try` is:


```julia
try

    iam(aws, Action = "CreateInstanceProfile", InstanceProfileName = name)

catch e
    try
        if e.code == "EntityAlreadyExists"
            e = nothing
        end
    end
    e == nothing || rethrow(e)
end
```


## `@repeat n try`

The `@repeat n try` macro retains the automatic `rethrow()` and `@ignore if` features of `@protected try` and adds support for automatic retry.

The following example tries four times to download an object from S3.
If the object was only recently created, the storage replica serving the 
`GET` request may not yet have a copy of it, so it is sometimes necessary to
retry the request. The `@delay_retry if` statement implements an
[exponential backoff algorithm](http://docs.aws.amazon.com/general/latest/gr/api-retries.html) with randomised jitter to provide timely retries while avoiding
un-due load on the server.

```julia
@repeat 4 try

   return s3(aws, "GET", bucket, path)

catch e
    @delay_retry if e.code in ["NoSuchBucket", "NoSuchKey"] end
end

```

If an exception is still raised on the fourth attempt `rethrow()` is called
so the exception can be dealt with by a different stack frame.

The code generated by the example above is:

```julia
begin

    delay = 0.05
    result = false

    for i = 1:4

        result = try

            return s3(aws,"GET",bucket,path)

        catch e

            try
                if e.code in ["NoSuchBucket","NoSuchKey"]
                    if (i < 4)
                        sleep(delay * (0.8 + (0.4 * rand())))
                        delay *= 10
                        continue
                    end
                end
            catch
            end

            e == nothing || rethrow(e)
        end
        break
    end

    result
end
```

The next example deals with two different temporary network/server
exceptions that warrant a delayed retry; and another that can be re-tried
immediately by re-directing to a different server.


```julia
@repeat 4 try 

    return http_attempt(request)

catch e

    @delay_retry if typeof(e) == UVError end

    @delay_retry if e.cause.status < 200 &&
                    e.cause.status >= 500 end

    @retry if e.cause.status in [301, 302, 307]
        request.uri = URI(headers(e)["Location"])
    end

end

```

The final example deals with creating an SQS queue. If the queue already
exists it must be deleted before creation is re-tried.

```julia
@repeat 4 try

    r = sqs(aws, Action = "CreateQueue", QueueName = name)
    return = XML(r)[:QueueUrl]

catch e

    @retry if e.code == "QueueAlreadyExists"
        sqs_delete_queue(aws, name)
    end

    @retry if e.code == "AWS.SimpleQueueService.QueueDeletedRecently"
        println("""Waiting 1 minute to re-create Queue "$name"...""")
        sleep(60)
    end
end

```

_The examples above are taken from [OCAWS.jl](https://github.com/samoconnor/OCAWS.jl)_
