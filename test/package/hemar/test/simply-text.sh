#answer="$(printf '%s' 'some text' | hemar -c)"
#
#expected="$(printf '%s' '[
#  {
#    "type":  "text",
#    "value": "some text"
#  }
#]')"
#
#json_diff "$answer" "$expected"
#
#answer="$(printf '%s' 'some [] {} text' | hemar -c)"
#
#expected="$(printf '%s' '[
#  {
#    "type":  "text",
#    "value": "some [] {} text"
#  }
#]')"
#
#json_diff "$answer" "$expected"
#
#answer="$(printf '%s' 'some {' | hemar -c)"
#
#expected="$(printf '%s' '[
#  {
#    "type":  "text",
#    "value": "some {"
#  }
#]')"
#
#json_diff "$answer" "$expected"
