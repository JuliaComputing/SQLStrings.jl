module SqlStrings

export @sql

"""
    Literal(str)

Literal string argument to `@sql`. These are literal query fragments of SQL
source text.
"""
struct Literal
    fragment::String

    Literal(val::AbstractString) = new(convert(String, val))
end

Literal(val) = Literal(string(val))

"""
    Sql

A query or query-fragment which keeps track of interpolations and will pass
them as SQL query parameters. Construct this type with the `@sql` macro.
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

"""
    sql`SOME SQL ... \$var`
    sql`SOME SQL ... \$(var...)`
    sql``

The `@sql` macro is a tool for tracking SQL query strings together with
their parameters, but without interpolating the parameters into the query
string directly. Instead, interpolations like `\$x` will result in the value of
`x` being passed as a query parameter. If you've got a collection of values to
interpolate into a comma separated context you can also use splatting syntax
within the interpolation, for example `insert into foo values(\$(x...))`.

Use this rather than direct string interpolation to prevent SQL injection
attacks and allow systematic conversion of Julia types into their SQL
equivalents.

Empty query fragments can be generated with ```sql`` ``` which is useful if you
must dynamically generate SQL code based on conditionals (however also consider
embedding any conditionals on the SQL side rather than in the Julia code.)
"""
macro sql(ex)
    if ex isa String
        args = [Literal(ex)]
    elseif ex isa Expr && ex.head == :string
        args = []
        for (i,arg) in enumerate(ex.args)
            if arg isa String
                push!(args, Literal(arg))
            else
                # Sanity check: arguments should not be quoted
                prev_quote = i > 1               && ex.args[i-1] isa String && endswith(ex.args[i-1], '\'')
                next_quote = i < length(ex.args) && ex.args[i+1] isa String && startswith(ex.args[i+1], '\'')
                if prev_quote || next_quote
                    error("""Interpolated arguments should not be quoted, but found quoting in subexpression
                             $(Expr(:string, ex.args[i-1:i+1]...))""")
                end
                if Meta.isexpr(arg, :...)
                    push!(args, :(SplatArgs($(esc(arg.args[1])))))
                else
                    push!(args, esc(arg))
                end
            end
        end
    else
        error("Unexpected expression passed to @sql: `$ex`")
    end
    quote
        Sql(process_args!([], $(args...)))
    end
end

macro sql()
    Sql([])
end

function Base.:*(x::Sql, y::Sql)
    Sql(vcat(x.args, [Literal(" ")], y.args))
end

function _prepare(query::Sql)
    querystr = ""
    arg_values = []
    i = 1
    for arg in query.args
        if arg isa Literal
            querystr *= arg.fragment
        else
            querystr *= "\$$i"
            push!(arg_values, arg)
            i += 1
        end
    end
    querystr, arg_values
end

function Base.show(io::IO, query::Sql)
    query, arg_values = _prepare(query)
    print(io, query)
    if !isempty(arg_values)
        args_str = join(["\$$i = $(repr(val))" for (i,val) in enumerate(arg_values)], "\n  ")
        print(io, "\n  ", args_str)
    end
end

end
