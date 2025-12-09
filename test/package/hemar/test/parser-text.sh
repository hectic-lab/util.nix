#!/bin/dash

# Test: Text parsing
# Tests that plain text is correctly parsed into text elements

log notice "test case: ${WHITE}simple text"
answer="$(printf '%s' 'some text' | hemar -c)"
expected='[{"type":"text","value":"some text"}]'
json_diff "$answer" "$expected"

log notice "test case: ${WHITE}text with brackets and braces"
answer="$(printf '%s' 'some [] {} text' | hemar -c)"
expected='[{"type":"text","value":"some [] {} text"}]'
json_diff "$answer" "$expected"

log notice "test case: ${WHITE}text ending with single brace"
answer="$(printf '%s' 'some {' | hemar -c)"
expected='[{"type":"text","value":"some {"}]'
json_diff "$answer" "$expected"

log notice "test case: ${WHITE}empty input"
answer="$(printf '%s' '' | hemar -c)"
expected='[]'
json_diff "$answer" "$expected"

log notice "test case: ${WHITE}text with newlines"
answer="$(printf 'line1\nline2\nline3' | hemar -c)"
expected='[{"type":"text","value":"line1\nline2\nline3"}]'
json_diff "$answer" "$expected"

log notice "test case: ${WHITE}text with special characters"
answer="$(printf '%s' 'text with "quotes" and \backslashes' | hemar -c)"
expected='[{"type":"text","value":"text with \"quotes\" and \\backslashes"}]'
json_diff "$answer" "$expected"

log notice "test passed"

