answer="$(echo 'some text' | hemar -c)"

expected="$(printf '[
  {
    "type":  "text",
    "value": "some text"
  }
]')"

json_diff "$answer" "$expected"

answer="$(echo 'some [] {} text' | hemar -c)"

expected="$(printf '[
  {
    "type":  "text",
    "value": "some [] {} text"
  }
]')"

json_diff "$answer" "$expected"

answer="$(echo 'some {' | hemar -c)"

expected="$(printf '[
  {
    "type":  "text",
    "value": "some {"
  }
]')"

json_diff "$answer" "$expected"
