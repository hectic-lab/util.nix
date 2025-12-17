#!/bin/dash

# $out  - nix derivation output
# $test - test and assertion file

HECTIC_NAMESPACE=test-laucher
export HECTIC_LOG=trace

# shellcheck disable=SC2154
test_derivation="$(basename "$test")"
test_name="${test_derivation#*-*-}"

set -eu

HECTIC_LOG=

log info 'start test pipeline (SQLite)'

# temp dirs
wd="$PWD"
db_file="$wd/test.db"

# Set up SQLite database URL
DATABASE_URL="sqlite://$db_file"
export DATABASE_URL

log info "using SQLite database: $db_file"
log info "run test ${WHITE}${test_name}${NC}"

# run test
mkdir './test'
cp -r "$test"/* './test/'
cd './test'
# shellcheck disable=SC1091
. './run.sh'

# shellcheck disable=SC2034
HECTIC_NAMESPACE=test-laucher

log info "finish test pipeline"

# success marker for Nix
# shellcheck disable=SC2154
mkdir -p "$out"

