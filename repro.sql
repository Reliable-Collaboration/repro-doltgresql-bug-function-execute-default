-- As postgres: a table, and a role that may read it.
CREATE TABLE t (x int);
INSERT INTO t VALUES (1), (2), (3);
CREATE ROLE reader LOGIN PASSWORD 'password';
GRANT SELECT ON t TO reader;

-- As reader: the rows, then how many there are.
\connect - reader
SELECT * FROM t ORDER BY x;
SELECT COUNT(*) FROM t;
