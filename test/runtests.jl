using Retry
using Base.Test

# write your own tests here

type TestException <: Exception
    code
end


@test_throws TestException  @protected try
                                throw(TestException(7))
                            catch e
                            end

@test_throws TestException  @protected try
                                throw(TestException(7))
                            catch e
                                @ignore if e.code == "Nothing to see here" end
                            end

@test   @protected try
            throw(TestException(7))
        catch e
            @ignore if e.code == 7 end
        end

@test   @protected try
            throw(TestException(7))
        catch e
            @ignore if typeof(e) == TestException end
        end

count = 0
@test_throws TestException  @repeat 4 try
                                global count += 1
                                throw(TestException(7))
                            catch e
                                @retry if e.code == 7 end
                            end
@test count == 4


count = 0
@test_throws TestException  @repeat 4 try
                                global count += 1
                                throw(TestException(5))
                            catch e
                                @retry if e.code == 7 end
                            end
@test count == 1

count = 0
@test @repeat 4 try
            global count += 1
            throw(TestException(7))
        catch e
            @ignore if e.code == 7 end
        end
@test count == 1

count = 0
start = time()
last_t = 0
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

count = 0
@test_throws TestException @repeat 2 try
                                global count += 1
                                throw(TestException(count))
                            catch e
                                @retry if e.code < 3 end
                                @ignore if e.code == 3 end
                            end
@test count == 2

count = 0
@test                       @repeat 3 try
                                global count += 1
                                throw(TestException(count))
                            catch e
                                @retry if e.code < 3 end
                                @ignore if e.code == 3 end
                            end
@test count == 3

count = 0
@test                       @repeat 10 try
                                global count += 1
                                throw(TestException(count))
                            catch e
                                @retry if e.code < 3 end
                                @ignore if e.code == 3 end
                            end
@test count == 3
