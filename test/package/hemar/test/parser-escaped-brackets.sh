#!/bin/dash

# Test: Escaped brackets
# Tests that {[ {[ ]} correctly outputs literal {[

log notice "test case: ${WHITE}escaped bracket"
answer="$(printf '%s' '{[ {[ ]}' | hemar -c)"
expected='[{"type":"text","value":"{["}]'
json_diff "$answer" "$expected"

log notice "test case: ${WHITE}escaped bracket with text"
answer="$(printf '%s' 'text {[ {[ ]} more text' | hemar -c)"
expected='[{"type":"text","value":"text {[ more text"}]'
json_diff "$answer" "$expected"

log notice "test case: ${WHITE}multiple escaped brackets"
answer="$(printf '%s' '{[ {[ ]} {[ {[ ]}' | hemar -c)"
expected='[{"type":"text","value":"{[ {["}]'
json_diff "$answer" "$expected"

log notice "test case: ${WHITE}escaped bracket merged with previous text"
answer="$(printf '%s' 'hello{[ {[ ]}world' | hemar -c)"
expected='[{"type":"text","value":"hello{[world"}]'
json_diff "$answer" "$expected"

log notice "test passed"

