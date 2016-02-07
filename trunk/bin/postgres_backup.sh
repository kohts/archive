#!/bin/sh

for d in `psql -c "COPY (select datname from pg_database where datistemplate = false) TO STDOUT WITH CSV"` ; do
    pg_dump $d | gzip -c > /backup/postgres/pg_dump.$d.`date +%s`.sql.gz
done
