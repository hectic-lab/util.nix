#!/bin/dash

# Test: Edge cases and error handling
# Tests various edge cases and malformed input

log notice "test case: ${WHITE}incomplete tag - single brace"
answer="$(printf '%s' 'text {' | hemar -c)"
expected='[{"type":"text","value":"text {"}]'
json_diff "$answer" "$expected"

log notice "test case: ${WHITE}incomplete tag - {[ without closing"
answer="$(printf '%s' 'text {[' | hemar -c)"
expected='[{"type":"text","value":"text {"}]'
json_diff "$answer" "$expected"

log notice "test case: ${WHITE}whitespace in tag"
answer="$(printf '%s' '{[  key  ]}' | hemar -c)"
expected='[{"type":"interpolation","path":"key"}]'
json_diff "$answer" "$expected"

log notice "test case: ${WHITE}newlines in tag"
answer="$(printf '{[\nkey\n]}' | hemar -c)"
expected='[{"type":"interpolation","path":"key"}]'
json_diff "$answer" "$expected"

log notice "test case: ${WHITE}empty interpolation tag"
answer="$(printf '%s' '{[ ]}' | hemar -c)"
expected='[{"type":"interpolation","path":""}]'
json_diff "$answer" "$expected"

log notice "test case: ${WHITE}text with only braces"
answer="$(printf '%s' '{ }' | hemar -c)"
expected='[{"type":"text","value":"{ }"}]'
json_diff "$answer" "$expected"

log notice "test case: ${WHITE}text with only brackets"
answer="$(printf '%s' '[ ]' | hemar -c)"
expected='[{"type":"text","value":"[ ]"}]'
json_diff "$answer" "$expected"

log notice "test case: ${WHITE}consecutive interpolations"
answer="$(printf '%s' '{[a]}{[b]}{[c]}' | hemar -c)"
expected='[{"type":"interpolation","path":"a"},{"type":"interpolation","path":"b"},{"type":"interpolation","path":"c"}]'
json_diff "$answer" "$expected"

log notice "test passed"

