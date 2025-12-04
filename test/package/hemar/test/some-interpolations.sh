#answer="$(printf '%s' 'text begind {[ "inn \\e\"r"-t\"ext ]}' | hemar -c)"
#
#expected="$(printf '%s' '[
#  {
#    "type": "text",
#    "value": "text begind "
#  },
#  {
#    "type": "interpolation",
#    "path": "inn \\e\"r-t\"ext"
#  }
#]')"
#
#json_diff "$answer" "$expected"
#
#[ "$(printf '%s' "$answer" | yq '.[1] | .path')" = 'inn \e"r-t"ext' ] || {
#  log error 'unexpected'
#  exit 1
#}
#
#answer="$(printf '%s' 'text begind {[ ["  "] ]}' | hemar -c)"
#
#expected="$(printf '%s' '[
#  {
#    "type": "text",
#    "value": "text begind "
#  },
#  {
#    "type": "interpolation",
#    "path": "[  ]"
#  }
#]')"
#
#json_diff "$answer" "$expected"
#
#answer="$(printf '%s' 'text begind {[ [" "\ ] ]}' | hemar -c)"
#
#json_diff "$answer" "$expected"
