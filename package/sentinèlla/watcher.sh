#!/bin/dash
# watcher.sh — p2p peer monitor; polls all peers discovered via DNS and notifies on status change
#
# Every node runs both probe (HTTP server) and watcher (this script).
# Peer discovery: a single DNS name with multiple A records is resolved via
# getent(1) on every poll cycle. Local IPs are detected automatically via
# hostname(1) and excluded so the node never polls itself.
# No central coordinator; all nodes are equal.
#
# DNS setup (external, any registrar, TTL 60):
#   peers.example.com  A  1.2.3.4
#   peers.example.com  A  5.6.7.8
#   peers.example.com  A  9.10.11.12
#
# Required env:
#   PEERS_DNS             DNS name that resolves to all peer IPs
#   TG_TOKEN              Telegram bot token
#   TG_CHAT_ID            Telegram chat ID
#
# Optional env:
#   SELF                  Override auto-detected local IP (useful behind NAT
#                         or with floating IPs where hostname -I is unreliable)
#   PEERS_PORT            default 5988
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
PEERS_DNS=${PEERS_DNS:-}
SELF=${SELF:-}
PEERS_PORT=${PEERS_PORT:-5988}
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

[ -n "$PEERS_DNS" ]  || { printf >&2 'PEERS_DNS not set\n';  exit 3; }
[ -n "$TG_TOKEN" ]   || { printf >&2 'TG_TOKEN not set\n';   exit 3; }
[ -n "$TG_CHAT_ID" ] || { printf >&2 'TG_CHAT_ID not set\n'; exit 3; }

# --- helpers ---

# local_ips — returns space-separated list of IPs assigned to local interfaces.
# If SELF is set it is used directly (useful behind NAT / floating IPs).
local_ips() {
  if [ -n "$SELF" ]; then
    printf '%s' "$SELF"
    return
  fi
  hostname -I 2>/dev/null || true
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

# resolve_peers — resolves PEERS_DNS to a newline-separated list of peer URLs,
# excluding all local IPs. Re-called every poll cycle so DNS changes are
# picked up without restarting the watcher.
resolve_peers() {
  getent hosts "$PEERS_DNS" \
    | awk '{print $1}' \
    | while IFS= read -r ip; do
        is_local_ip "$ip" || printf '%s://%s:%s\n' "$PEERS_SCHEME" "$ip" "$PEERS_PORT"
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

# server_status_message(prefix, peer_url, ok, total, fail_list)
server_status_message() {
  printf '%s: %s [%s/%s]%s' "${1:?}" "${2:?}" "${3:?}" "${4:?}" "$5"
}

# --- main loop ---

trap 'rm -f "$tmpb" 2>/dev/null' EXIT INT HUP

while :; do
  log info "polling peers via ${WHITE}${PEERS_DNS}${NC} every ${WHITE}${POLLING_INTERVAL_SEC}${NC}s"

  peers=$(resolve_peers) || peers=""

  if [ -z "$peers" ]; then
    log warn "no peers resolved from ${WHITE}${PEERS_DNS}${NC} (all IPs are local or DNS returned nothing)"
  fi

  printf '%s\n' "$peers" | while IFS= read -r url; do
    [ -n "$url" ] || continue

    tmpb=$(mktemp) || exit 1
    set -- curl -sS -m "$TIMEOUT" -w '%{http_code}' -o "$tmpb"
    [ -n "$PEERS_TOKEN" ] && set -- "$@" -H "Authorization: Basic $PEERS_TOKEN"
    set -- "$@" "$url"
    code=$("$@" 2>/dev/null) || code="000"
    body=$(cat "$tmpb"); rm -f "$tmpb"

    ok="down"; total=0; good=0
    if [ "$code" = "200" ]; then
      summary=$(printf '%s' "$body" | parse_summary || true)
      [ -n "$summary" ] && { total=${summary%% *}; good=${summary#* }; }
      [ "$total" -eq "$good" ] && ok="up"
    fi

    msg_prefix=$([ "$ok" = "up" ] && printf '%s' "$PREFIX_OK" || printf '%s' "$PREFIX_FAIL")
    fail_list=""
    if [ "$ok" = "down" ] && [ -n "$body" ]; then
      fails=$(printf '%s' "$body" | list_failures | sed 's/[ ]$//')
      [ -n "$fails" ] && fail_list=" — ${fails}"
    fi
    msg=$(server_status_message "$msg_prefix" "$url" "$good" "$total" "$fail_list")

    sfile="${STATE_DIR}/$(sid "$url").state"
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
