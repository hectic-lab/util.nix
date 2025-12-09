#!/bin/dash

# Test: For loops (MVP feature - currently unimplemented)
# These tests document expected behavior when for loops are implemented

log notice "test case: ${WHITE}for loop structure (should fail until implemented)"
if answer="$(printf '%s' '{[ for i in items ]}' | hemar -c 2>&1)"; then
  log error "test failed: ${WHITE}for loop should not be implemented yet, but parser succeeded"
  exit 1
fi
log notice "test case: ${WHITE}for loop correctly rejected (expected behavior)"

log notice "test case: ${WHITE}for loop with done (should fail until implemented)"
if answer="$(printf '{[ for i in items ]}\n  content\n{[ done ]}' | hemar -c 2>&1)"; then
  log error "test failed: ${WHITE}for loop should not be implemented yet, but parser succeeded"
  exit 1
fi
log notice "test case: ${WHITE}for loop with done correctly rejected (expected behavior)"

# When for loops are implemented, these should be the expected outputs:
# 
# log notice "test case: ${WHITE}simple for loop"
# answer="$(printf '{[ for i in items ]}\n{[ done ]}' | hemar -c)"
# expected='[{"type":"section","variable":"i","path":"items","body":[]}]'
# json_diff "$answer" "$expected"
#
# log notice "test case: ${WHITE}for loop with content"
# answer="$(printf '{[ for i in items ]}\n  hello {[i]}\n{[ done ]}' | hemar -c)"
# expected='[{"type":"section","variable":"i","path":"items","body":[{"type":"text","value":"  hello "},{"type":"interpolation","path":"i"}]}]'
# json_diff "$answer" "$expected"
#
# log notice "test case: ${WHITE}nested for loops"
# answer="$(printf '{[ for i in items ]}\n  {[ for j in i.subitems ]}\n    {[j]}\n  {[ done ]}\n{[ done ]}' | hemar -c)"
# expected='[{"type":"section","variable":"i","path":"items","body":[{"type":"text","value":"  "},{"type":"section","variable":"j","path":"i.subitems","body":[{"type":"text","value":"    "},{"type":"interpolation","path":"j"}]}]}]'
# json_diff "$answer" "$expected"

log notice "test passed (for loops not yet implemented - this is expected)"

