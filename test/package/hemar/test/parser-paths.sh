#!/bin/dash

# Test: Path parsing
# Tests various path formats: quoted strings, indices, mixed paths

log notice "test case: ${WHITE}quoted string in path"
answer="$(printf '%s' '{["key with spaces"]}' | hemar -c)"
expected='[{"type":"interpolation","path":[{"type":"key","key":"key with spaces"}]}]'
json_diff "$answer" "$expected"

log notice "test case: ${WHITE}quoted dot in path"
answer="$(printf '%s' '{[".key"]}' | hemar -c)"
expected='[{"type":"interpolation","path":[{"type":"key","key":".key"}]}]'
json_diff "$answer" "$expected"

log notice "test case: ${WHITE}quoted vs unquoted dot"
answer="$(printf '%s' '{["."]} {[.]}' | hemar -c)"
expected='[{"type":"interpolation","path":[{"type":"key","key":"."}]},{"type":"text","value":" "},{"type":"interpolation","path":[{"type":"root"}]}]'
json_diff "$answer" "$expected"

log notice "test case: ${WHITE}path with index"
answer="$(printf '%s' '{[key[0]]}' | hemar -c)"
expected='[{"type":"interpolation","path":[{"type":"key","key":"key"},{"type":"index","index":0}]}]'
json_diff "$answer" "$expected"

log notice "test case: ${WHITE}path with multiple indices"
answer="$(printf '%s' '{[[0][1][2]]}' | hemar -c)"
expected='[{"type":"interpolation","path":[{"type":"index","index":0},{"type":"index","index":1},{"type":"index","index":2}]}]'
json_diff "$answer" "$expected"

log notice "test case: ${WHITE}path with negative index"
answer="$(printf '%s' '{[key[-1]]}' | hemar -c)"
expected='[{"type":"interpolation","path":[{"type":"key","key":"key"},{"type":"index","index":-1}]}]'
json_diff "$answer" "$expected"

log notice "test case: ${WHITE}complex path with mixed segments"
answer="$(printf '%s' '{["key".subkey[0]."subsubkey"]}' | hemar -c)"
expected='[{"type":"interpolation","path":[{"type":"key","key":"key"},{"type":"key","key":"subkey"},{"type":"index","index":0},{"type":"key","key":"subsubkey"}]}]'
json_diff "$answer" "$expected"

log notice "test case: ${WHITE}quoted string with escaped quote"
answer="$(printf '%s' '{["key""with""quotes"]}' | hemar -c)"
expected='[{"type":"interpolation","path":[{"type":"key","key":"key\"with\"quotes"}]}]'
json_diff "$answer" "$expected"

log notice "test passed"

