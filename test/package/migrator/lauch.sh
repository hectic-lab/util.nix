#!/bin/dash

# $out  - nix derivation output
# $test - test and assertion file

HECTIC_NAMESPACE=test-laucher
export HECTIC_LOG=trace

test_derivation="$(basename "$test")"
test_name="${test_derivation#*-*-}"

set -eu

root_dir="$(dirname $0)"

HECTIC_LOG=

# save path to pg_ctl in case $PATH will change
PG_CTL="$(command -v pg_ctl)"
cleanup() {
  "$PG_CTL" -D "$data" -m fast -w stop
}

log info 'start test pipeline'

# temp dirs
wd="$PWD"
data="$wd/data"
sockdir="$wd/sock"
db="testdb"
mkdir -p "$data" "$sockdir"

# initdb
initdb -D "$data" --no-locale -E UTF8 >/dev/null

# trust local auth for the test
{
  echo "unix_socket_directories = '$sockdir'"
  echo "listen_addresses = ''"
} >> "$data/postgresql.conf"
sed -i "1ilocal all all trust" "$data/pg_hba.conf"

# start cluster
pg_ctl -D "$data" -o "-F" -w start
trap cleanup EXIT

user="$(id -un)"

# bootstrap DB
createdb -h "$sockdir" -U "$user" "$db"

psql -h "$sockdir" -d testdb -v ON_ERROR_STOP=1 -c 'select 1;' >/dev/null

export PGHOST="$sockdir"
export PGPORT=5432
export PGUSER="$user"
export PGDATABASE="$db"

DATABASE_URL="postgresql://${PGUSER}@/${PGDATABASE}?host=${PGHOST}&port=${PGPORT}"
export DATABASE_URL

log info "run test ${WHITE}${test_name}${NC}"

# run test
mkdir './test'
cp -r "$test"/* './test/'
cd './test'
. './run.sh'

HECTIC_NAMESPACE=test-laucher

log info "finish test pipeline"

# success marker for Nix
# shellcheck disable=SC2154
mkdir -p "$out"
