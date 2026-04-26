#!/bin/dash
# Test: watcher writes a state file after polling a peer
#
# Setup:
#   - Start a probe on 127.0.0.1:15990
#   - Stub getent to resolve peers.test -> 127.0.0.1 (the probe) and 10.0.0.1 (fake peer)
#   - Stub hostname to return 10.0.0.1 as the local IP so 10.0.0.1 is excluded
#     and 127.0.0.1 (the real probe) is kept as a peer
#   - Assert a state file appears in STATE_DIR within 15s

log notice "test case: ${WHITE}watcher writes state file after first successful poll"

PORT=15990
export PORT URLS="" VOLUMES="/"

probe &
probe_pid=$!
trap 'kill "$probe_pid" 2>/dev/null; kill "$watcher_pid" 2>/dev/null; rm -rf "$stub_dir" "$state_dir"' EXIT INT HUP

sleep 2

# Create stubs directory
stub_dir=$(mktemp -d)

# Stub getent: returns two IPs for peers.test
cat >"${stub_dir}/getent" <<'EOF'
#!/bin/sh
if [ "$1" = "hosts" ] && [ "$2" = "peers.test" ]; then
  printf '127.0.0.1 peers.test\n'
  printf '10.0.0.1 peers.test\n'
else
  /usr/bin/getent "$@"
fi
EOF
chmod +x "${stub_dir}/getent"

# Stub hostname: -I returns 10.0.0.1 so watcher excludes it and keeps 127.0.0.1
cat >"${stub_dir}/hostname" <<'EOF'
#!/bin/sh
case "$1" in
  -I) printf '10.0.0.1\n' ;;
  *)  /bin/hostname "$@" ;;
esac
EOF
chmod +x "${stub_dir}/hostname"

state_dir=$(mktemp -d)

export PEERS_DNS="peers.test"
export PEERS_PORT="$PORT"
export PEERS_SCHEME="http"
export TG_TOKEN="test-token"
export TG_CHAT_ID="test-chat"
export STATE_DIR="$state_dir"
export POLLING_INTERVAL_SEC="1"
export SPAM="0"
unset SELF  # ensure auto-detection is used

PATH="${stub_dir}:${PATH}" watcher &
watcher_pid=$!

log info "waiting for state file in $state_dir ..."
peer_url="http://127.0.0.1:${PORT}"
state_file="${state_dir}/$(printf '%s' "$peer_url" | cksum | awk '{print $1}').state"
wait_for_file "$state_file" 15

state=$(cat "$state_file")
log info "state file content: $WHITE$state"

case "$state" in
  up:*|down:*) log info "PASS: state file has expected format" ;;
  *) log error "unexpected state file content: $state"; exit 1 ;;
esac

log notice "test passed"
