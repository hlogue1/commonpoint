#!/bin/bash
# usage: runmig.sh <db> <dir>  -- applies the "up" half of each *.sql (before tern marker), in order
db=$1; dir=$2
P="psql -h /tmp -p 5499 -U postgres -v ON_ERROR_STOP=1 -q"
$P -c "drop database if exists $db" -c "create database $db" >/dev/null
$P -d $db -c "create extension if not exists pgcrypto; create or replace function uuidv7() returns uuid language sql volatile as 'select gen_random_uuid()';" >/dev/null
for f in $(ls $dir/*.sql | sort); do
  up=$(awk '/---- create above \/ drop below ----/{exit} {print}' "$f")
  out=$(printf '%s\n' "$up" | $P -d $db 2>&1) && echo "OK   $(basename $f)" || { echo "FAIL $(basename $f)"; echo "$out" | head -5; }
done
