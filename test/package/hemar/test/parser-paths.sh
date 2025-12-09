#!/bin/dash

# Test: Path parsing
# Tests various path formats: quoted strings, indices, mixed paths

log notice "test case: ${WHITE}quoted string in path"
answer="$(printf '%s' '{["key with spaces"]}' | hemar -c)"
expected='[{"type":"interpolation","path":"key with spaces"}]'
json_diff "$answer" "$expected"

log notice "test case: ${WHITE}quoted dot in path"
answer="$(printf '%s' '{[".key"]}' | hemar -c)"
expected='[{"type":"interpolation","path":".key"}]'
json_diff "$answer" "$expected"

log notice "test case: ${WHITE}quoted vs unquoted dot"
answer="$(printf '%s' '{["."]} {[.]}' | hemar -c)"
expected='[{"type":"interpolation","path":"."},{"type":"text","value":" "},{"type":"interpolation","path":"."}]'
json_diff "$answer" "$expected"

log notice "test case: ${WHITE}path with index"
answer="$(printf '%s' '{[key[0]]}' | hemar -c)"
expected='[{"type":"interpolation","path":"key[0]"}]'
json_diff "$answer" "$expected"

log notice "test case: ${WHITE}path with multiple indices"
answer="$(printf '%s' '{[[0][1][2]]}' | hemar -c)"
expected='[{"type":"interpolation","path":"[0][1][2]"}]'
json_diff "$answer" "$expected"

log notice "test case: ${WHITE}path with negative index"
answer="$(printf '%s' '{[key[-1]]}' | hemar -c)"
expected='[{"type":"interpolation","path":"key[-1]"}]'
json_diff "$answer" "$expected"

log notice "test case: ${WHITE}complex path with mixed segments"
answer="$(printf '%s' '{["key".subkey[0]."subsubkey"]}' | hemar -c)"
expected='[{"type":"interpolation","path":"key.subkey[0].subsubkey"}]'
json_diff "$answer" "$expected"

log notice "test case: ${WHITE}quoted string with escaped quote"
answer="$(printf '%s' '{["key""with""quotes"]}' | hemar -c)"
expected='[{"type":"interpolation","path":"key\"with\"quotes"}]'
json_diff "$answer" "$expected"

log notice "test passed"

