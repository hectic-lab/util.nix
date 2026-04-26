#!/bin/dash
# Test: probe responds on GET /status with valid JSON when URLS is empty

log notice "test case: ${WHITE}probe GET /status returns JSON with empty checks"

# start probe on a free port
PORT=15988
export PORT URLS="" VOLUMES="/"

probe &
probe_pid=$!
trap 'kill $probe_pid 2>/dev/null; exit' EXIT INT HUP

# wait for probe to be ready
sleep 2

response=$(curl -sS --max-time 5 "http://127.0.0.1:${PORT}/status")
log info "response: $WHITE$response"

# must be valid JSON with summary.total == 0
total=$(printf '%s' "$response" | jq -r '.summary.total')
assert_eq "summary.total is 0 when URLS empty" "$total" "0"

ok=$(printf '%s' "$response" | jq -r '.summary.ok')
assert_eq "summary.ok is 0 when URLS empty" "$ok" "0"

log notice "test passed"
