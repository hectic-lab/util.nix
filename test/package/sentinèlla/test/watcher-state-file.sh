#!/bin/dash
# Test: watcher writes a state file after polling a peer
#
# Setup:
#   - Start a probe on 127.0.0.1:15990
#   - Stub dig to return SRV record for _sentinella._tcp.peers.test
#   - Stub getent to resolve node-a.peers.test -> 127.0.0.1 (the probe)
#   - Set SELF=10.0.0.1 so the local IP is excluded and 127.0.0.1 is kept as peer
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

# Stub dig: returns SRV record
# The watcher calls: $DIG +short +time=3 +tries=2 SRV "$PEERS_SRV"
# SRV format: "priority weight port target."
cat >"${stub_dir}/dig" <<'EOF'
#!/bin/sh
printf '0 10 15990 node-a.peers.test.\n'
EOF
chmod +x "${stub_dir}/dig"

# Stub getent: resolves the SRV target to the probe IP
# The watcher calls: $GETENT hosts "$target"
cat >"${stub_dir}/getent" <<'EOF'
#!/bin/sh
if [ "$1" = "hosts" ] && [ "$2" = "node-a.peers.test" ]; then
  printf '127.0.0.1 node-a.peers.test\n'
else
  /usr/bin/getent "$@"
fi
EOF
chmod +x "${stub_dir}/getent"

state_dir=$(mktemp -d)

export PEERS_SRV="_sentinella._tcp.peers.test"
export PEERS_SCHEME="http"
export TG_TOKEN="test-token"
export TG_CHAT_ID="test-chat"
export STATE_DIR="$state_dir"
export POLLING_INTERVAL_SEC="1"
export SPAM="0"
export SELF="10.0.0.1"  # exclude this IP, keep 127.0.0.1 as peer
export DIG="${stub_dir}/dig"
export GETENT="${stub_dir}/getent"

watcher &
watcher_pid=$!

log info "waiting for state file in $state_dir ..."
peer_host="node-a.peers.test"
state_file="${state_dir}/$(printf '%s' "$peer_host" | cksum | awk '{print $1}').state"
wait_for_file "$state_file" 15

state=$(cat "$state_file")
log info "state file content: $WHITE$state"

case "$state" in
  up:*|down:*) log info "PASS: state file has expected format" ;;
  *) log error "unexpected state file content: $state"; exit 1 ;;
esac

log notice "test passed"
