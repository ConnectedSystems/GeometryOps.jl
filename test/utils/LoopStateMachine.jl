using Test
using GeometryOps.LoopStateMachine: @controlflow, Continue, Break

@testset "Continue action" begin
    count = 0
    f(i) = begin
        count += 1
        if i == 3
            return Continue()
        end
        count += 1
    end
    for i in 1:5
        @controlflow f(i)
    end
    @test count == 9 # Adds 1 for each iteration, but skips second +1 on i=3
end

@testset "Break action" begin
    count = 0
    function f(i)
        count += 1
        if i == 3
            return Break()
        end
        count += 1
    end
    for i in 1:5
        @controlflow f(i)
    end
    @test count == 5 # Counts up to i=3, adding 2 for i=1,2 and 1 for i=3
end

@testset "Return value" begin
    results = Int[]
    for i in 1:3
        val = @controlflow begin
            i * 2
        end
        push!(results, val)
    end
    @test results == [2, 4, 6]
end

