using SQLStrings
using Test
using UUIDs

querystr(q) = SQLStrings.prepare(q)[1]
queryargs(q) = SQLStrings.prepare(q)[2]

@testset "SQLStrings.jl" begin
    x = 1
    y = 2
    q1 = sql`select a where b=$x and c=$(x+y)`
    @test querystr(q1) == raw"select a where b=$1 and c=$2"
    @test queryargs(q1) == [x, x+y]

    # Test concatenation
    q2 = sql`select a` * sql`where b=$x`
    @test querystr(q2) == raw"select a where b=$1"
    @test queryargs(q2) == [x,]

    # Test that interpolating queries into queries works
    where_clause = sql`where b=$x`
    and_clause = sql`and c=$y`
    empty_clause = sql``
    q3 = sql`select a $where_clause $and_clause $empty_clause`
    @test querystr(q3) == raw"select a where b=$1 and c=$2 "
    @test queryargs(q3) == [x, y]

    # On occasion, we need to interpolate in a literal string rather than use a
    # parameter. Test that interpolating Literal works for this case.
    column = "x"
    @test querystr(sql`select $(SQLStrings.Literal(column)) from a`) ==
        raw"select x from a"

    # Test splatting syntax
    z = [1,"hi"]
    q4 = sql`insert into foo values($(z...))`
    @test querystr(q4) == raw"insert into foo values($1,$2)"
    @test queryargs(q4) == z

    # Test that Literal turns values into strings
    @test SQLStrings.Literal(:col_name).fragment == "col_name"
    @test SQLStrings.Literal(1).fragment == "1"

    # Test dollars inside SQL strings - the $x here should be a literal.
    q5 = sql`select $y where x = '$x'`
    @test querystr(q5) == raw"select $1 where x = '$x'"
    @test queryargs(q5) == [y,]
    # Escaping of $
    q6 = sql`some literal \$a`
    @test querystr(q6) == raw"some literal $a"

    SQLStrings.allow_dollars_in_strings[] = false
    @test_throws LoadError @macroexpand sql`select $y where x = '$x'`
    SQLStrings.allow_dollars_in_strings[] = true
end

