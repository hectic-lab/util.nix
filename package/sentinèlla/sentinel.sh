#!/bin/dash
# sentinel.sh — polls probe backends (/status) and notifies on status change via Telegram
# Env:
#   SERVERS="http://host1:8080,http://host2:8080"
#   TOKENS="-,b64token2"             # CSV aligned with SERVERS; "-" means no auth
#   TOKEN="..."                      # Telegram bot token
#   CHAT_ID="..."                    # Telegram chat id
#   TIMEOUT=5                        # curl timeout seconds (default 5)
#   POLLING_INTERVAL_SEC=3           # default 3
#   STATE_DIR=/tmp/sentinel          # default /tmp/sentinel

set -eu

TIMEOUT=${TIMEOUT:-5}
POLLING_INTERVAL_SEC=${POLLING_INTERVAL_SEC:-3}
STATE_DIR=${STATE_DIR:-/tmp/sentinel}
SERVERS=${SERVERS:-}
TOKENS=${TOKENS:-}
TOKEN=${TOKEN:-}
CHAT_ID=${CHAT_ID:-}

[ -n "$SERVERS" ] || { printf >&2 'SERVERS not set\n'; exit 1; }

# If TOKENS unset, synthesize "-" for each server
if [ -z "$TOKENS" ]; then
  n=$(printf '%s\n' "$SERVERS" | tr -cd ',' | wc -c | awk '{print $1+1}')
  TOKENS=$(awk -v n="$n" 'BEGIN{for(i=1;i<=n;i++){printf("-"); if(i<n)printf(",")}}')
fi

mkdir -p "$STATE_DIR"

# --- helpers ---

# get_csv VAR idx -> echo idx-th field (1-based) from CSV string VAR
get_csv() {
  # shellcheck disable=SC2001
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
