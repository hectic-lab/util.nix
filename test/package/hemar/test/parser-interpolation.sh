#!/bin/dash

# Test: Interpolation parsing
# Tests that {[path]} tags are correctly parsed into interpolation elements

log notice "test case: ${WHITE}simple interpolation"
answer="$(printf '%s' '{[hello]}' | hemar -c)"
expected='[{"type":"interpolation","path":[{"type":"key","key":"hello"}]}]'
json_diff "$answer" "$expected"

log notice "test case: ${WHITE}interpolation with text before and after"
answer="$(printf '%s' 'foo {[bar]} baz' | hemar -c)"
expected='[{"type":"text","value":"foo "},{"type":"interpolation","path":[{"type":"key","key":"bar"}]},{"type":"text","value":" baz"}]'
json_diff "$answer" "$expected"

log notice "test case: ${WHITE}root path"
answer="$(printf '%s' '{[.]}' | hemar -c)"
expected='[{"type":"interpolation","path":[{"type":"root"}]}]'
json_diff "$answer" "$expected"

log notice "test case: ${WHITE}simple path"
answer="$(printf '%s' '{[key]}' | hemar -c)"
expected='[{"type":"interpolation","path":[{"type":"key","key":"key"}]}]'
json_diff "$answer" "$expected"

log notice "test case: ${WHITE}dot-separated path"
answer="$(printf '%s' '{[key.subkey]}' | hemar -c)"
expected='[{"type":"interpolation","path":[{"type":"key","key":"key"},{"type":"key","key":"subkey"}]}]'
json_diff "$answer" "$expected"

log notice "test case: ${WHITE}long path"
answer="$(printf '%s' '{[key.subkey.subsubkey]}' | hemar -c)"
expected='[{"type":"interpolation","path":[{"type":"key","key":"key"},{"type":"key","key":"subkey"},{"type":"key","key":"subsubkey"}]}]'
json_diff "$answer" "$expected"

log notice "test case: ${WHITE}multiple interpolations"
answer="$(printf '%s' '{[a]} {[b]} {[c]}' | hemar -c)"
expected='[{"type":"interpolation","path":[{"type":"key","key":"a"}]},{"type":"text","value":" "},{"type":"interpolation","path":[{"type":"key","key":"b"}]},{"type":"text","value":" "},{"type":"interpolation","path":[{"type":"key","key":"c"}]}]'
json_diff "$answer" "$expected"

log notice "test passed"

