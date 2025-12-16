#!/bin/dash

# $test - test and assertion file

json_diff() {
    temp1=$(mktemp)
    temp2=$(mktemp)

    # Normalize JSON strings for comparison
    printf '%s' "$1" | yq -I=0 -o=j . >"$temp1" 2>/dev/null || {
        log error "first argument is not valid JSON: $WHITE$1"
        exit 1
    }
    printf '%s' "$2" | yq -I=0 -o=j . >"$temp2" 2>/dev/null || {
        log error "second argument is not valid JSON: $WHITE$2"
        exit 1
    }

    if ! diff -q "$temp1" "$temp2" >/dev/null 2>&1; then
        log error "JSON mismatch:"
        log error "  Expected: $WHITE$(cat "$temp2")"
        log error "  Got:      $WHITE$(cat "$temp1")"
        exit 1
    fi
}

# run test
#mkdir './test'
#cp -r "$test"/* './test/'
#cd './test'
#. './run.sh'
