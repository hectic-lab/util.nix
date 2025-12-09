# shellcheck disable=SC2034
AS_LIBRARY=1
# shellcheck disable=SC1090
. "$(which hemar)"

log notice "test case: ${WHITE}double quote escaping"
input='text with "quotes"'
if ! answer=$(json_escape "$input"); then
  log error "test failed: ${WHITE}error during json_escape call"
  exit 1
fi

expected='text with \"quotes\"'
if [ "$answer" != "$expected" ]; then
  log error "test failed: ${WHITE}wrong answer. Expected: $expected, Got: $answer"
  exit 1
fi

log notice "test case: ${WHITE}backslash escaping"
input='text with \backslash'
if ! answer=$(json_escape "$input"); then
  log error "test failed: ${WHITE}error during json_escape call"
  exit 1
fi

expected='text with \\backslash'
if [ "$answer" != "$expected" ]; then
  log error "test failed: ${WHITE}wrong answer. Expected: $expected, Got: $answer"
  exit 1
fi

log notice "test case: ${WHITE}newline escaping"
input="line1
line2"
if ! answer=$(json_escape "$input"); then
  log error "test failed: ${WHITE}error during json_escape call"
  exit 1
fi

expected='line1\nline2'
if [ "$answer" != "$expected" ]; then
  log error "test failed: ${WHITE}wrong answer. Expected: $expected, Got: $answer"
  exit 1
fi

log notice "test case: ${WHITE}carriage return escaping"
input=$(printf 'line1\rline2')
if ! answer=$(json_escape "$input"); then
  log error "test failed: ${WHITE}error during json_escape call"
  exit 1
fi

expected='line1\rline2'
if [ "$answer" != "$expected" ]; then
  log error "test failed: ${WHITE}wrong answer. Expected: $expected, Got: $answer"
  exit 1
fi

log notice "test case: ${WHITE}tab escaping"
input="text	with	tabs"
if ! answer=$(json_escape "$input"); then
  log error "test failed: ${WHITE}error during json_escape call"
  exit 1
fi

expected='text\twith\ttabs'
if [ "$answer" != "$expected" ]; then
  log error "test failed: ${WHITE}wrong answer. Expected: $expected, Got: $answer"
  exit 1
fi

log notice "test case: ${WHITE}control character escaping"
# NOTE: Test with a control character (bell, 0x07)
input=$(printf 'text\007with\007control')
if ! answer=$(json_escape "$input"); then
  log error "test failed: ${WHITE}error during json_escape call"
  exit 1
fi

# NOTE: Control character should be escaped as \u0007
expected='text\u0007with\u0007control'
if [ "$answer" != "$expected" ]; then
  log error "test failed: ${WHITE}wrong answer. Expected: $expected, Got: $answer"
  exit 1
fi

log notice "test case: ${WHITE}complex string with multiple special chars"
input='text with "quotes" and \backslashes
and newlines	and tabs'
if ! answer=$(json_escape "$input"); then
  log error "test failed: ${WHITE}error during json_escape call"
  exit 1
fi

expected='text with \"quotes\" and \\backslashes\nand newlines\tand tabs'
if [ "$answer" != "$expected" ]; then
  log error "test failed: ${WHITE}wrong answer. Expected: $expected, Got: $answer"
  exit 1
fi

log notice "test case: ${WHITE}empty string"
input=''
if ! answer=$(json_escape "$input"); then
  log error "test failed: ${WHITE}error during json_escape call"
  exit 1
fi

if [ -n "$answer" ]; then
  log error "test failed: ${WHITE}empty string should produce empty output"
  exit 1
fi

log notice "test case: ${WHITE}plain text (no escaping needed)"
input='plain text without special chars'
if ! answer=$(json_escape "$input"); then
  log error "test failed: ${WHITE}error during json_escape call"
  exit 1
fi

if [ "$answer" != "$input" ]; then
  log error "test failed: ${WHITE}plain text should remain unchanged. Expected: $input, Got: $answer"
  exit 1
fi

log notice "test passed"

