#!/bin/dash

# $test - test and assertion file

json_diff() {
    temp1=$(mktemp)
    temp2=$(mktemp)

    yq -I=0 -o=j -n "$1" >"$temp1"
    yq -I=0 -o=j -n "$2" >"$temp2"

    if ! diff -q "$temp1" "$temp2"; then
	log error "$(yq -o=j -n "$1")" and "$(yq -o=j -n "$2")"
	exit 1
    fi
}

# run test
mkdir './test'
cp -r "$test"/* './test/'
cd './test'
. './run.sh'
