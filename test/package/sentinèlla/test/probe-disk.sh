#!/bin/dash
# Test: probe GET /disk returns JSON with at least one volume entry

log notice "test case: ${WHITE}probe GET /disk returns volume data"

PORT=15989
export PORT URLS="" VOLUMES="/"

probe &
probe_pid=$!
trap 'kill $probe_pid 2>/dev/null; exit' EXIT INT HUP

sleep 2

response=$(curl -sS --max-time 5 "http://127.0.0.1:${PORT}/disk")
log info "response: $WHITE$response"

count=$(printf '%s' "$response" | jq -r '.volumes | length')
log info "volume count: $WHITE$count"

if [ "$count" -lt 1 ]; then
  log error "expected at least 1 volume, got $count"
  exit 1
fi
log info "PASS: at least one volume returned"

# each entry must have a mount field
mount=$(printf '%s' "$response" | jq -r '.volumes[0].mount')
if [ -z "$mount" ] || [ "$mount" = "null" ]; then
  log error "volumes[0].mount is missing or null"
  exit 1
fi
log info "PASS: volumes[0].mount = $mount"

log notice "test passed"
