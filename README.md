# SqlStrings

This package provides the `@sql_cmd` macro to allow SQL query strings to be
constructed by normal-looking string interpolation but without danger of SQL
injection attacks.

[![Little Bobby Tables](https://imgs.xkcd.com/comics/exploits_of_a_mom.png)](https://xkcd.com/327)

`@sql_cmd` is quite simple — it understands only the basic rules of SQL
quoting and Julia string interpolation, but does no other parsing of the source
text. In this sense it is quite similar to `Base.Cmd` - it keeps any literal
SQL text you write as-is and captures the Julia-level string interpolations
in a safe way.

## Simple usage

To use with a given database backend, you'll need a small amount of integration
code. In the examples below we'll use with LibPQ.jl and a `runquery()` function
(hopefully integration will be automatic in future).

```julia
import LibPQ

runquery(conn, sql::SqlStrings.Sql)
    query, args = SqlStrings.prepare(sql)
    LibPQ.execute(conn, query, args)
end
```

Creating a table and inserting some values

```julia
conn = LibPQ.connection(your_connection_string)

runquery(conn, sql`CREATE TABLE foo (email text, userid integer)`)

for (email,id) in [ ("admin@example.com", 1)
                    ("foo@example.com",   2)]
    runquery(conn, sql`INSERT INTO foo VALUES ($email, $id)`)
end
```

Thence:

```julia
julia> runquery(conn, sql`SELECT * FROM foo`) |> DataFrame
2×2 DataFrame
 Row │ email              userid
     │ String?            Int32?
─────┼───────────────────────────
   1 │ admin@example.com       1
   2 │ foo@example.com         2
```

## Howto: Inserting values from a Julia array into a row

In some circumstances it can be useful to use splatting syntax to interpolate a
Julia collection into a comma-separated list of values. Generally simple scalar
parameters should be preferred for simplicity, but splatting can be useful on
occasion:

```julia
email_and_id = ("bar@example.com", 3)
runquery(conn, sql`INSERT INTO foo VALUES ($(email_and_id...))`)
```

## Howto: Using the `in` operator with a Julia collection

There's two ways to do this. First, using `in` and splatting syntax

```julia
julia> ids = (1,2)
       runquery(conn, sql`SELECT * FROM foo WHERE userid IN ($(ids...))`) |> DataFrame
       2×2 DataFrame
        Row │ email              userid
            │ String?            Int32?
       ─────┼───────────────────────────
          1 │ admin@example.com       1
          2 │ foo@example.com         2
```

Second, using the SQL `any` operator and simply passing a single SQL array parameter:

```julia
julia> ids = [1,2]
       runquery(conn, sql`SELECT * FROM foo WHERE userid = any($ids)`) |> DataFrame
       2×2 DataFrame
        Row │ email              userid
            │ String?            Int32?
       ─────┼───────────────────────────
          1 │ admin@example.com       1
          2 │ foo@example.com         2
```

## Howto: Building up a query from fragments

On occasion you might want to dynamically build up a complicated query from
fragments of SQL source text. To do this, the result of `@sql_cmd` can be
interpolated into a larger query as follows.

```julia
conn = LibPQ.connection(your_connection_string)

some_condition = true

x = 100
x = 20
# Example of an optional clauses - use empty sql` to disable it.
and_clause = some_condition ? sql`AND y=$y` : sql``

# Interpolation of values produces SQL parameters; interpolating sql`
# fragments adds them to the query.
q = sql`SELECT * FROM table WHERE x=$x $and_clause`
runquery(conn, q)
```

A word of warning that constructing SQL logic with Julia-level logic can make
the code quite hard to understand. It can be worth considering writing one
larger SQL query which does more of the logic on the SQL side.

