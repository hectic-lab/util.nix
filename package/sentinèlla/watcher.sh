#!/bin/dash
# watcher.sh — p2p peer monitor; polls all peers discovered via DNS SRV records
# and notifies on status change via Telegram.
#
# Every node runs both probe (HTTP server) and watcher (this script).
# Peer discovery: a single SRV record name resolved on every poll cycle.
# Each SRV entry yields (priority, weight, port, target-hostname); the target
# is resolved to an IP via getent and excluded if it belongs to this node.
# No central coordinator; all nodes are equal.
#
# DNS setup (any registrar, TTL 60):
#   _sentinella._tcp.example.com.  SRV  0 10 5988 node-a.peers.example.com.
#   _sentinella._tcp.example.com.  SRV  0 10 5988 node-b.peers.example.com.
#   node-a.peers.example.com.      A    1.2.3.4
#   node-b.peers.example.com.      A    5.6.7.8
#
# Required env:
#   PEERS_SRV             SRV record name (e.g. _sentinella._tcp.example.com)
#   TG_TOKEN              Telegram bot token
#   TG_CHAT_ID            Telegram chat ID
#
# Optional env:
#   SELF                  Override auto-detected local IPs (space-separated)
#   PEERS_SCHEME          default http
#   PEERS_TOKEN           Basic Auth token sent to all peers; omit for no auth
#   TIMEOUT               curl timeout seconds (default 5)
#   POLLING_INTERVAL_SEC  default 3
#   STATE_DIR             default /var/lib/sentinella
#   SPAM                  if 1, notify on every poll regardless of state change

set -eu

PREFIX_OK="OK  "
PREFIX_FAIL="FAIL"

TIMEOUT=${TIMEOUT:-5}
POLLING_INTERVAL_SEC=${POLLING_INTERVAL_SEC:-3}
PEERS_SRV=${PEERS_SRV:-}
SELF=${SELF:-}
PEERS_SCHEME=${PEERS_SCHEME:-http}
PEERS_TOKEN=${PEERS_TOKEN:-}
TG_TOKEN=${TG_TOKEN:-}
TG_CHAT_ID=${TG_CHAT_ID:-}
SPAM=${SPAM:-0}

STATE_DIR=${STATE_DIR:-/var/lib/sentinella}
mkdir -p "$STATE_DIR" 2>/dev/null || {
  STATE_DIR="$HOME/.local/$(basename "$STATE_DIR")"
  mkdir -p "$STATE_DIR"
}

[ -n "$PEERS_SRV" ]  || { printf >&2 'PEERS_SRV not set\n';  exit 3; }
[ -n "$TG_TOKEN" ]   || { printf >&2 'TG_TOKEN not set\n';   exit 3; }
[ -n "$TG_CHAT_ID" ] || { printf >&2 'TG_CHAT_ID not set\n'; exit 3; }

# --- helpers ---

# local_ips — space-separated list of IPs assigned to this node.
local_ips() {
  if [ -n "$SELF" ]; then
    printf '%s' "$SELF"
    return
  fi
  # ip -o -4 addr show: "<idx>: <iface>    inet <ip>/<prefix> ..."
  ip -o addr show 2>/dev/null \
    | awk '$3 ~ /^inet6?$/ { sub(/\/.*/, "", $4); print $4 }' \
    | tr '\n' ' '
}

# is_local_ip(ip) — returns 0 if ip belongs to this node
is_local_ip() {
  _target=${1:?}
  _locals=$(local_ips)
  case " $_locals " in
    *" $_target "*) return 0 ;;
  esac
  return 1
}

# resolve_peers — SRV-resolves PEERS_SRV, then A-resolves each target.
# Emits "host port ip" per non-local peer, one per line.
resolve_peers() {
  # host -t SRV output:
  #   <name> has SRV record <prio> <weight> <port> <target>.
  host -t SRV "$PEERS_SRV" 2>/dev/null \
    | awk '/has SRV record/ { sub(/\.$/, "", $NF); print $(NF-1), $NF }' \
    | while IFS=' ' read -r port target; do
        [ -n "$target" ] || continue
        ip=$(getent hosts "$target" | awk '{print $1; exit}')
        [ -n "$ip" ] || { log warn "could not resolve ${WHITE}${target}${NC}"; continue; }
        is_local_ip "$ip" && continue
        printf '%s %s %s\n' "$target" "$port" "$ip"
      done
}

notify() {
  msg=${1:?}
  curl -sS -m "$TIMEOUT" -X POST \
    "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
    -d "chat_id=${TG_CHAT_ID}" \
    --data-urlencode "text=${msg}" >/dev/null \
    || log error "notify failed: $msg"
  log notice "notify message: ${WHITE}${msg}${NC}"
}

# sid(url) — stable filename token for state files
sid() { printf '%s' "$1" | cksum | awk '{print $1}'; }

# <stream> | parse_summary
parse_summary() {
  jq -r '.status.summary | "\(.total) \(.ok)"'
}

# <stream> | list_failures — extract failing URL(code) pairs from JSON body
list_failures() {
  awk '
    BEGIN { FS="\""; u=""; c="" }
    /"url":/  { u=$4 }
    /"code":/ { c=$0; sub(/.*"code":/, "", c); sub(/,.*/, "", c) }
    /"ok":false/ { if (u != "") { printf "%s(%s) ", u, c; u=""; c="" } }
  '
}

# server_status_message(prefix, peer_label, ok, total, fail_list)
server_status_message() {
  printf '%s: %s [%s/%s]%s' "${1:?}" "${2:?}" "${3:?}" "${4:?}" "$5"
}

# --- main loop ---

trap 'rm -f "$tmpb" 2>/dev/null' EXIT INT HUP

while :; do
  log info "polling peers via SRV ${WHITE}${PEERS_SRV}${NC} every ${WHITE}${POLLING_INTERVAL_SEC}${NC}s"

  peers=$(resolve_peers) || peers=""

  if [ -z "$peers" ]; then
    log warn "no peers resolved from ${WHITE}${PEERS_SRV}${NC} (all targets local or DNS empty)"
  fi

  printf '%s\n' "$peers" | while IFS=' ' read -r host port ip; do
    [ -n "$host" ] || continue

    url="${PEERS_SCHEME}://${ip}:${port}"
    label="${host} (${ip})"

    tmpb=$(mktemp) || exit 1
    set -- curl -sS -m "$TIMEOUT" -w '%{http_code}' -o "$tmpb"
    [ -n "$PEERS_TOKEN" ] && set -- "$@" -H "Authorization: Basic $PEERS_TOKEN"
    set -- "$@" "${url}/status"
    code=$("$@" 2>/dev/null) || code="000"
    body=$(cat "$tmpb"); rm -f "$tmpb"

    ok="down"; total=0; good=0
    if [ "$code" = "200" ]; then
      summary=$(printf '%s' "$body" | parse_summary 2>/dev/null || true)
      if [ -n "$summary" ]; then
        _total=${summary%% *}
        _good=${summary#* }
        case "$_total" in ''|*[!0-9]*) _total=0 ;; esac
        case "$_good"  in ''|*[!0-9]*) _good=0  ;; esac
        total=$_total
        good=$_good
      fi
      [ "$total" -eq "$good" ] && ok="up"
    fi

    msg_prefix=$([ "$ok" = "up" ] && printf '%s' "$PREFIX_OK" || printf '%s' "$PREFIX_FAIL")
    fail_list=""
    if [ "$ok" = "down" ] && [ -n "$body" ]; then
      fails=$(printf '%s' "$body" | list_failures | sed 's/[ ]$//')
      [ -n "$fails" ] && fail_list=" — ${fails}"
    fi
    msg=$(server_status_message "$msg_prefix" "$label" "$good" "$total" "$fail_list")

    sfile="${STATE_DIR}/$(sid "$host").state"
    last=""; [ -f "$sfile" ] && last=$(cat "$sfile")
    cur="${ok}:${good}/${total}:${code}"
    if [ "$cur" != "$last" ] || [ "$SPAM" = "1" ]; then
      notify "$msg"
      printf '%s' "$cur" >"$sfile"
    else
      log info "no change: ${WHITE}${msg}${NC}"
    fi
  done

  sleep "$POLLING_INTERVAL_SEC"
done
