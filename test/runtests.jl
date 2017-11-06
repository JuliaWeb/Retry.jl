#==============================================================================#
# runtests.jl
#
# Tests for Retry.jl
#
# Copyright Sam O'Connor 2014 - All rights reserved
#==============================================================================#


using Retry
using Base.Test


mutable struct TestException <: Exception
    code
end


# @protected try re-throws the exception by default...

@test_throws TestException  @protected try
                                throw(TestException(7))
                            catch e
                            end


# @protected try re-throws the exception if the @ignore condition is false...

@test_throws TestException  @protected try
                                throw(TestException(7))
                            catch e
                                @ignore if e.code == "Nothing to see here" end
                            end


# Exception ignored by error code...

@test   @protected try
            throw(TestException(7))
        catch e
            @ignore if e.code == 7 end
        end


# Exception ignored by type...

@test   @protected try
            throw(TestException(7))
        catch e
            @ignore if typeof(e) == TestException end
        end


# Try 4 times and re-thow exception...

count = 0
@test_throws TestException  @repeat 4 try
                                global count += 1
                                throw(TestException(7))
                            catch e
                                @retry if e.code == 7 end
                            end
@test count == 4


# Only try 1 time and re-thow exception if @retry condition is not met...

count = 0
@test_throws TestException  @repeat 4 try
                                global count += 1
                                throw(TestException(5))
                            catch e
                                @retry if e.code == 7 end
                            end
@test count == 1


# Only try 1 time and re-thow exception if @retry condition is not met...

count = 0
@test @repeat 4 try
            global count += 1
            throw(TestException(7))
        catch e
            @ignore if e.code == 7 end
        end
@test count == 1


# Check that retry delay gets longer each time...

count = 0
start = time()
last_t = 0
delay = -1
i = -1
@test_throws TestException @repeat 3 try
                                global count, start, last_t
                                t = time() - start
                                @test t > last_t * 9.9
                                start = time()
                                count += 1
                                throw(TestException(7))
                            catch e
                                @delay_retry if e.code == 7 end
                            end
@test count == 3

# Check for leakage of macro local variables...
@test delay == -1
@test i == -1


# Re-throw after 2 attempts...

count = 0
@test_throws TestException @repeat 2 try
                                global count += 1
                                throw(TestException(count))
                            catch e
                                @retry if e.code < 3 end
                                @ignore if e.code == 3 end
                            end
@test count == 2


# @ignore condition met after 3 attempts...

count = 0
@test                       @repeat 3 try
                                global count += 1
                                throw(TestException(count))
                            catch e
                                @retry if e.code < 3 end
                                @ignore if e.code == 3 end
                            end
@test count == 3


# No more attempts after @ignore condition met...

count = 0
@test                       @repeat 10 try
                                global count += 1
                                throw(TestException(count))
                            catch e
                                @retry if e.code < 3 end
                                @ignore if e.code == 3 end
                            end
@test count == 3



#==============================================================================#
# End of file.
#==============================================================================#
