#!/bin/dash
# launch.sh — sets up helpers and runs the test pointed to by $test

# assert_eq(label, got, expected)
assert_eq() {
  label=${1:?}
  got=${2:?}
  expected=${3:?}
  if [ "$got" != "$expected" ]; then
    log error "FAIL: $label"
    log error "  expected: $WHITE$expected"
    log error "  got:      $WHITE$got"
    exit 1
  fi
  log info "PASS: $label"
}

# assert_file_contains(label, file, pattern)
assert_file_contains() {
  label=${1:?}
  file=${2:?}
  pattern=${3:?}
  if ! grep -q "$pattern" "$file" 2>/dev/null; then
    log error "FAIL: $label — pattern '$pattern' not found in $file"
    exit 1
  fi
  log info "PASS: $label"
}

# wait_for_file(file, timeout_sec)
wait_for_file() {
  file=${1:?}
  timeout=${2:-10}
  i=0
  while [ $i -lt "$timeout" ]; do
    [ -f "$file" ] && return 0
    sleep 1
    i=$((i+1))
  done
  log error "timeout waiting for file: $file"
  exit 1
}

# run the actual test
. "$test/run.sh"
