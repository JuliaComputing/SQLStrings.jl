using SqlStrings
using Test
using UUIDs

querystr(q) = SqlStrings._prepare(q)[1]
queryargs(q) = SqlStrings._prepare(q)[2]

@testset "SqlStrings.jl" begin
    x = 1
    y = 2
    q1 = @sql "select a where b=$x and c=$(x+y)"
    @test querystr(q1) == raw"select a where b=$1 and c=$2"
    @test queryargs(q1) == [x, x+y]

    # Test concatenation
    q2 = @sql("select a") * @sql("where b=$x")
    @test querystr(q2) == raw"select a where b=$1"
    @test queryargs(q2) == [x,]

    # Test that interpolating queries into queries works
    where_clause = @sql "where b=$x"
    and_clause = @sql "and c=$y"
    empty_clause = @sql()
    q3 = @sql "select a $where_clause $and_clause $empty_clause"
    @test querystr(q3) == raw"select a where b=$1 and c=$2 "
    @test queryargs(q3) == [x, y]

    # On occasion, we need to interpolate in a literal string rather than use a
    # parameter. Test that interpolating Literal works for this case.
    column = "x"
    @test querystr(@sql "select $(SqlStrings.Literal(column)) from a") ==
        raw"select x from a"

    # Test that erroneously adding quoting produces an error message
    @test_throws LoadError @macroexpand @sql "select $y where x = '$x'"

    # Test splatting syntax
    z = [1,"hi"]
    q4 = @sql "insert into foo values($(z...))"
    @test querystr(q4) == raw"insert into foo values($1,$2)"
    @test queryargs(q4) == z

    # Test that Literal turns values into strings
    @test SqlStrings.Literal(:col_name).fragment == "col_name"
    @test SqlStrings.Literal(1).fragment == "1"
end

