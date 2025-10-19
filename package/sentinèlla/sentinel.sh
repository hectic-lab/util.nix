#!/bin/dash
# sentinel.sh — polls probe backends (/status) and notifies on status change via Telegram
# Env:
#   SERVERS="http://host1:8080,http://host2:8080"
#   TOKENS="-,b64token2"             # CSV aligned with SERVERS; "-" means no auth
#   TG_TOKEN="..."                   # Telegram bot token
#   TG_CHAT_ID="..."                 # Telegram chat id
#   TIMEOUT=5                        # curl timeout seconds (default 5)
#   POLLING_INTERVAL_SEC=3           # default 3
#   STATE_DIR=/var/lib/sentinel      # default /var/lib/sentinel
#   SPAM=0                           # if 1 will notify every poling, default 0

set -eu

TIMEOUT=${TIMEOUT:-5}
POLLING_INTERVAL_SEC=${POLLING_INTERVAL_SEC:-3}
SERVERS=${SERVERS:-}
TOKENS=${TOKENS:-}
TOKEN=${TOKEN:-}
CHAT_ID=${CHAT_ID:-}
SPAM=${SPAM:-0}

STATE_DIR=${STATE_DIR:-/var/lib/sentinel}
mkdir -p "$STATE_DIR" 2>/dev/null || {
  # TODO: some sort of message?
  STATE_DIR="$HOME/.local/$(basename "$STATE_DIR")"
  mkdir -p "$STATE_DIR"
}

mkdir -p "$STATE_DIR" 2>/dev/null || mkdir -p "$HOME/.local/$(basename "$STATE_DIR")"

[ -n "$SERVERS" ] || { printf >&2 'SERVERS not set\n'; exit 1; }
[ -n "$TOKEN" ]   || { printf >&2 'TOKEN not set\n';   exit 1; }
[ -n "$CHAT_ID" ] || { printf >&2 'CHAT_ID not set\n'; exit 1; }

# If TOKENS unset, synthesize "-" for each server
if [ -z "$TOKENS" ]; then
  n=$(printf '%s\n' "$SERVERS" | tr -cd ',' | wc -c | awk '{print $1+1}')
  TOKENS=$(awk -v n="$n" 'BEGIN{for(i=1;i<=n;i++){printf("-"); if(i<n)printf(",")}}')
fi

# --- helpers ---

# get_csv(csv_variable, index)
# echo idx-th field (1-based) from CSV string VAR
get_csv() {
  printf '%s' "$1" | sed 's/,/\n/g' | awk -v n="$2" 'NR==n{print; exit}'
}

notify() {
  msg=$1
  if [ -n "$TOKEN" ] && [ -n "$CHAT_ID" ]; then
    curl -sS -m "$TIMEOUT" -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
      -d "chat_id=${CHAT_ID}" \
      --data-urlencode "text=${msg}" >/dev/null || printf >&2 'notify failed: %s\n' "$msg"
  else
    printf >&2 '%s\n' "$msg"
  fi
}

# sid(text)
sid() { printf '%s' "$1" | cksum | awk '{print $1}'; }

parse_summary() {
  sed -n 's/.*"summary":{"total":\([0-9][0-9]*\),"ok":\([0-9][0-9]*\)}.*/\1 \2/p'
}

list_failures() {
  awk '
    BEGIN{FS="\""; u=""; c=""}
    /"url":/ {u=$4}
    /"code":/ {c=$0; sub(/.*"code":/,"",c); sub(/,.*/,"",c)}
    /"ok":false/ { if(u!=""){ printf "%s(%s) ", u, c; u=""; c="" } }
  '
}

# --- main loop ---
while :; do
  log info "pooling ${WHITE}${POLLING_INTERVAL_SEC}${NC} sec"
  i=1
  while :; do
    srv=$(get_csv "$SERVERS" "$i") || true
    [ -n "${srv:-}" ] || break
    tok=$(get_csv "$TOKENS" "$i") || tok="-"

    url="${srv%/}/status"
    auth_h=""
    [ "${tok}" != "-" ] && [ -n "${tok}" ] && auth_h="-H Authorization: Basic\ $tok"

    tmpb=$(mktemp) || exit 1
    code=$(sh -c "curl -sS -m \"$TIMEOUT\" -w '%{http_code}' -o \"$tmpb\" $auth_h \"$url\"") || code="000"
    body=$(cat "$tmpb"); rm -f "$tmpb"

    log info "server ${WHITE}${srv}${NC}\ncode ${WHITE}${code}${NC}\nbody ${WHITE}${body}${NC}"

    ok="down"; tot=0; good=0
    if [ "$code" = "200" ]; then
      s=$(printf '%s' "$body" | parse_summary || true)
      [ -n "$s" ] && { tot=${s%% *}; good=${s#* }; }
      [ "$tot" -eq "$good" ] && ok="up"
    fi

    msg_prefix=$( [ "$ok" = "up" ] && printf 'OK' || printf 'FAIL' )
    fail_list=""
    if [ "$ok" = "down" ] && [ -n "$body" ]; then
      fails=$(printf '%s' "$body" | list_failures | sed 's/[ ]$//')
      [ -n "$fails" ] && fail_list=" — ${fails}"
    fi
    msg=$(printf '%s: %s [%s/%s]%s' "$msg_prefix" "$srv" "$good" "$tot" "$fail_list")

    sfile="${STATE_DIR}/$(sid "$srv").state"
    last=""; [ -f "$sfile" ] && last=$(cat "$sfile")
    cur="${ok}:${good}/${tot}:${code}"
    if [ "$cur" != "$last" ]; then
      notify "$msg"
      printf '%s' "$cur" >"$sfile"
    fi

    i=$((i+1))
  done

  sleep "$POLLING_INTERVAL_SEC"
done
