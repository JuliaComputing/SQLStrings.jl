module SQLStrings

export @sql_cmd

"""
    Literal(str)

Literal string argument to `@sql_cmd`. These are literal query fragments of SQL
source text.
"""
struct Literal
    fragment::String

    Literal(val::AbstractString) = new(convert(String, val))
end

Literal(val) = Literal(string(val))

"""
    Sql

An SQL query or query-fragment which keeps track of interpolations and will
pass them as SQL query parameters. Construct this type with the `@sql_cmd`
macro.
"""
struct Sql
    args::Vector
end

struct SplatArgs
    args
end

function process_args!(processed)
    return processed
end

function process_args!(processed, a, args...)
    push!(processed, a)
    return process_args!(processed, args...)
end

# Query fragments can be interpolated into other queries
function process_args!(processed, a::Sql, args...)
    return process_args!(processed, a.args..., args...)
end

function process_args!(processed, splat::SplatArgs, args...)
    for (i,a) in enumerate(splat.args)
        process_args!(processed, a)
        if i < length(splat.args)
            push!(processed, Literal(","))
        end
    end
    return process_args!(processed, args...)
end

function parse_interpolations(str, allow_dollars_in_strings)
    args = []
    i = 1
    literal_start = i
    literal_end = 0
    in_singlequote = false
    prev_was_backslash = false
    while i <= lastindex(str)
        c = str[i]
        if !allow_dollars_in_strings && in_singlequote && c == '$'
            error("""Interpolated arguments should not be quoted, but found quoting in sql`$str`
                     subexpression starting at `$(str[i:end])`""")
        end
        if c == '$' && !in_singlequote
            if prev_was_backslash
                literal_end = prevind(str, literal_end, 1)
                if literal_start <= literal_end
                    push!(args, Literal(str[literal_start:literal_end]))
                end
                literal_start = i
                i = nextind(str, i)
            else
                if literal_start <= literal_end
                    push!(args, Literal(str[literal_start:literal_end]))
                end
                (interpolated_arg, i) = Meta.parse(str, i+1; greedy=false)
                if Meta.isexpr(interpolated_arg, :...)
                    push!(args, :(SplatArgs($(esc(interpolated_arg.args[1])))))
                else
                    push!(args, esc(interpolated_arg))
                end
                literal_start = i
            end
        else
            if c == '\''
                # We assume standard SQL which uses '' rather than \' for
                # escaping quotes.
                in_singlequote = !in_singlequote
            end
            literal_end = i
            i = nextind(str, i)
        end
        prev_was_backslash = c == '\\'
    end
    if literal_start <= literal_end
        push!(args, Literal(str[literal_start:literal_end]))
    end
    args
end

"""
    allow_dollars_in_strings[] = true

Set this parsing option to `false` to disallow dollars inside SQL strings, for
example disallowing the `'\$s'` in

    sql`select * from foo where s = '\$s'`

When converting code from plain string-based interpolation, it's helpful to
have a macro-expansion-time sanity check that no manual quoting of interpolated
arguments remains.
"""
const allow_dollars_in_strings = Ref(true)

"""
    sql`SOME SQL ... \$var`
    sql`SOME SQL ... \$(var...)`
    sql`SOME SQL ... 'A \$literal string'`
    sql``

The `@sql_cmd` macro is a tool for tracking SQL query strings together with
their parameters, but without interpolating the parameters into the query
string directly. Instead, interpolations like `\$x` will result in the value of
`x` being passed as a query parameter. If you've got a collection of values to
interpolate into a comma separated context you can also use splatting syntax
within the interpolation, for example `insert into foo values(\$(x...))`.

Use this rather than direct string interpolation to prevent SQL injection
attacks and allow systematic conversion of Julia types into their SQL
equivalents via the database layer, rather than via `string()`.

Empty query fragments can be generated with ```sql`` ``` which is useful if you
must dynamically generate SQL code based on conditionals. However you should
also consider embedding any conditionals on the SQL side rather than in the
Julia code.

*Interpolations are ignored* inside standard SQL Strings with a single quote,
so using `'A \$literal string'` will include `\$literal` rather than the value
of the variable `literal`. If converting code from using raw strings, you may
have needed to quote interpolations. In that case you can check your conversion
by setting `SQLStrings.allow_dollars_in_strings[] = false`.

If you need to include a literal `\$` in the SQL code outside a string, you can
escape it with `\\\$`.
"""
macro sql_cmd(str)
    args = parse_interpolations(str, allow_dollars_in_strings[])
    quote
        Sql(process_args!([], $(args...)))
    end
end

function Base.:*(x::Sql, y::Sql)
    Sql(vcat(x.args, [Literal(" ")], y.args))
end

default_placeholder_string(i) = "\$$i"

function prepare(sql::Sql, to_placeholder = default_placeholder_string)
    querystr = ""
    arg_values = []
    i = 1
    for arg in sql.args
        if arg isa Literal
            querystr *= arg.fragment
        else
            querystr *= to_placeholder(i)
            push!(arg_values, arg)
            i += 1
        end
    end
    querystr, arg_values
end

function Base.show(io::IO, sql::Sql)
    query, arg_values = prepare(sql)
    print(io, query)
    if !isempty(arg_values)
        args_str = join(["\$$i = $(repr(val))" for (i,val) in enumerate(arg_values)], "\n  ")
        print(io, "\n  ", args_str)
    end
end

end
