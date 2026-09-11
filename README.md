# DoltgreSQL 1.3.1: a role with SELECT on a table is refused COUNT(*) on it: "permission denied for routine count"

On DoltgreSQL 1.3.1, a login role granted `SELECT` on a table can read its rows, but `SELECT COUNT(*)` on
the same table fails with `ERROR:  permission denied for routine count`. PostgreSQL 18.6 answers `3`: it
grants the `EXECUTE` privilege on functions to `PUBLIC` by default, so the role needs no grant to call
`count`.

## Reproduce it

You need Docker and a POSIX shell: Linux, macOS, or Windows with WSL. The first run downloads the images.

```sh
git clone https://github.com/Reliable-Collaboration/repro-doltgresql-bug-function-execute-default.git
cd repro-doltgresql-bug-function-execute-default
./repro.sh
```

`repro.sh` starts a throwaway PostgreSQL 18.6 container and a throwaway DoltgreSQL 1.3.1 container, waits
until both accept connections, runs [`repro.sql`](repro.sql) in each with the `psql` client inside that
container, prints the two outputs side by side, and removes the containers. It exits 0 when DoltgreSQL's
output is identical to PostgreSQL's, and 1 when it differs, as it does on 1.3.1.

`repro.sql` switches from `postgres` to a second login role with psql's `\connect`. Every role's password
is `password`, so the `PGPASSWORD` given to `psql` covers each login.

To try another DoltgreSQL release, name its image:

```sh
DOLTGRESQL_IMAGE=dolthub/doltgresql:latest ./repro.sh
```

### Without the script

The same steps by hand, from the repository directory. On DoltgreSQL:

```sh
docker run -d --name repro-doltgresql-bug-function-execute-default-doltgresql -e DOLTGRES_PASSWORD=password dolthub/doltgresql:1.3.1
docker cp repro.sql repro-doltgresql-bug-function-execute-default-doltgresql:/tmp/repro.sql
docker exec -t -e PGPASSWORD=password repro-doltgresql-bug-function-execute-default-doltgresql sh -c 'psql -X -P pager=off -h 127.0.0.1 -U postgres -d postgres --echo-all -f /tmp/repro.sql < /dev/null'
docker rm -f repro-doltgresql-bug-function-execute-default-doltgresql
```

On PostgreSQL:

```sh
docker run -d --name repro-doltgresql-bug-function-execute-default-postgres -e POSTGRES_PASSWORD=password postgres:18.6-bookworm
docker cp repro.sql repro-doltgresql-bug-function-execute-default-postgres:/tmp/repro.sql
docker exec -t -e PGPASSWORD=password repro-doltgresql-bug-function-execute-default-postgres sh -c 'psql -X -P pager=off -h 127.0.0.1 -U postgres -d postgres --echo-all -f /tmp/repro.sql < /dev/null'
docker rm -f repro-doltgresql-bug-function-execute-default-postgres
```

If `docker exec` answers that the connection was refused, the server is still starting: wait a few
seconds and run it again. The `< /dev/null` keeps `psql` from printing a version line at each `\connect`:
without it, the DoltgreSQL image's psql 17.11 also prints
`psql (17.11 (Debian 17.11-0+deb13u1), server 15.17)` after each `\connect`.

## The test

[`repro.sql`](repro.sql):

```sql
-- As postgres: a table, and a role that may read it.
CREATE TABLE t (x int);
INSERT INTO t VALUES (1), (2), (3);
CREATE ROLE reader LOGIN PASSWORD 'password';
GRANT SELECT ON t TO reader;

-- As reader: the rows, then how many there are.
\connect - reader
SELECT * FROM t ORDER BY x;
SELECT COUNT(*) FROM t;
```

## Expected behavior

`reader` reads the three rows and counts them. This is what PostgreSQL 18.6 does, from the line where
`reader` logs in:

```
-- As reader: the rows, then how many there are.
\connect - reader
You are now connected to database "postgres" as user "reader".
SELECT * FROM t ORDER BY x;
 x 
---
 1
 2
 3
(3 rows)

SELECT COUNT(*) FROM t;
 count 
-------
     3
(1 row)
```

No grant beyond `SELECT` is needed, because PostgreSQL grants `EXECUTE` on functions to `PUBLIC`. From
[its documentation](https://www.postgresql.org/docs/18/ddl-priv.html): "For other types of objects, the
default privileges granted to `PUBLIC` are as follows: `CONNECT` and `TEMPORARY` (create temporary
tables) privileges for databases; `EXECUTE` privilege for functions and procedures; and `USAGE`
privilege for languages and data types (including domains)."

## Actual behavior

`reader` reads the three rows, but counting them fails. This is what DoltgreSQL 1.3.1 does, from the line
where `reader` logs in:

```
-- As reader: the rows, then how many there are.
\connect - reader
You are now connected to database "postgres" as user "reader".
SELECT * FROM t ORDER BY x;
 x 
---
 1
 2
 3
(3 rows)

SELECT COUNT(*) FROM t;
psql:/tmp/repro.sql:10: ERROR:  permission denied for routine count
```

## Side by side

The full output of `./repro.sh`:

```
Starting postgres:18.6-bookworm@sha256:1c59e2c3c818eaa0f0628f695b36e7c9e362d6b219b36a54a32df645cbd7e1af
Starting dolthub/doltgresql:1.3.1@sha256:6c85cb1f35beabf47f094336a420255130b841b1645f36d79ef046276af36851

Left: PostgreSQL. Right: DoltgreSQL. Lines that differ are marked with |.

-- As postgres: a table, and a role that may read it.         -- As postgres: a table, and a role that may read it.
CREATE TABLE t (x int);                                       CREATE TABLE t (x int);
CREATE TABLE                                                  CREATE TABLE
INSERT INTO t VALUES (1), (2), (3);                           INSERT INTO t VALUES (1), (2), (3);
INSERT 0 3                                                    INSERT 0 3
CREATE ROLE reader LOGIN PASSWORD 'password';                 CREATE ROLE reader LOGIN PASSWORD 'password';
CREATE ROLE                                                   CREATE ROLE
GRANT SELECT ON t TO reader;                                  GRANT SELECT ON t TO reader;
GRANT                                                         GRANT
-- As reader: the rows, then how many there are.              -- As reader: the rows, then how many there are.
\connect - reader                                             \connect - reader
You are now connected to database "postgres" as user "reade   You are now connected to database "postgres" as user "reade
SELECT * FROM t ORDER BY x;                                   SELECT * FROM t ORDER BY x;
 x                                                             x 
---                                                           ---
 1                                                             1
 2                                                             2
 3                                                             3
(3 rows)                                                      (3 rows)

SELECT COUNT(*) FROM t;                                       SELECT COUNT(*) FROM t;
 count                                                      | psql:/tmp/repro.sql:10: ERROR:  permission denied for routi
-------                                                     <
     3                                                      <
(1 row)                                                     <
                                                            <

Result: DoltgreSQL's output differs from PostgreSQL's on 1 line(s), marked with |.
```

## Other observations

Each was run on both servers, with the `psql` client in each image. PostgreSQL ran every statement named
here without an error; the results below are DoltgreSQL's, for a role without any `EXECUTE` grant unless
a grant is named.

- With `GRANT USAGE ON SCHEMA public` and `GRANT SELECT ON ALL TABLES IN SCHEMA public` instead of
  `GRANT SELECT ON t`, `COUNT(*)` is refused the same way.
- Other aggregates and a window function are refused the same way: `count(x)`, `sum(x)`, `min(x)`,
  `max(x)`, `avg(x)`, `bool_and(x > 0)` and `row_number() OVER (ORDER BY x)`, which answers
  `permission denied for routine row_number`.
- No table is needed: `SELECT count(*) FROM (VALUES (1), (2)) AS v(x)` is refused too.
- `SELECT current_user` and `SELECT session_user` are both refused with
  `permission denied for routine current_user`.
- A built-in named with its schema is refused: `SELECT pg_catalog.lower('A')` answers
  `permission denied for routine lower`, while `SELECT lower('A')` answers `a`.
- These run without an error: `now()`, `lower('A')`, `upper('a')`, `length('a')`, `abs(-1)`,
  `coalesce(NULL, 1)`, `version()`, `current_database()`, `generate_series(1, 2)`, `array_agg(x)` and
  `string_agg(x::text, ',')`.
- A function created by `postgres` is refused too: after
  `CREATE FUNCTION add1(i int) RETURNS int LANGUAGE plpgsql AS $$ BEGIN RETURN i + 1; END $$`,
  `SELECT add1(1)` answers `permission denied for routine add1`.
- Granting the role `EXECUTE ON ALL FUNCTIONS IN SCHEMA pg_catalog` changes nothing: `COUNT(*)`,
  `sum(x)`, `current_user` and `add1(1)` are still refused.
- Granting the role `EXECUTE ON ALL FUNCTIONS IN SCHEMA public` makes `COUNT(*)`, `sum(x)`,
  `current_user` and `add1(1)` run, although `count` and `sum` are built-in functions. The same grant to
  `PUBLIC` makes `COUNT(*)` and `add1(1)` run for a role that holds only `SELECT` on `t`.
- Once `current_user` runs, it answers `r3@127.0.0.1` for a role named `r3`, where PostgreSQL answers
  `r3`.
- Granting the role `EXECUTE ON FUNCTION add1(int)` makes `add1(1)` run and leaves `COUNT(*)` refused.
- On PostgreSQL, `SELECT acldefault('f', 'postgres'::regrole)` answers
  `{=X/postgres,postgres=X/postgres}`, `EXECUTE` for `PUBLIC`. DoltgreSQL answers
  `function: 'acldefault' not found`, and `function: 'has_function_privilege' not found` to
  `has_function_privilege('reader', 'lower(text)', 'EXECUTE')`, which PostgreSQL answers `t`.

## Environment

- DoltgreSQL 1.3.1, the newest release when this was written: image `dolthub/doltgresql:1.3.1`, digest
  `sha256:6c85cb1f35beabf47f094336a420255130b841b1645f36d79ef046276af36851`. Its bundled `psql` is 17.11.
- PostgreSQL 18.6: image `postgres:18.6-bookworm`, digest
  `sha256:1c59e2c3c818eaa0f0628f695b36e7c9e362d6b219b36a54a32df645cbd7e1af`. Its bundled `psql` is 18.6.
- Reproduced on 2026-09-11 (UTC) with Docker 29.7.2 on Linux x86_64 (Ubuntu 26.04.1 LTS under WSL 2).
