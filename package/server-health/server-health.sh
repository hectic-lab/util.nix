#!/bin/sh
# router.sh — POSIX sh HTTP backend (for socat)
# usage: socat -T5 -t5 TCP-LISTEN:${port},reuseaddr,fork EXEC:"sh ${currentfile}"
# Routes:
#   GET /status  -> check $URLS (0/0 if unset)
#   GET /disk    -> check $VOLUMES (all if unset)
# Env:
#   URLS="http://..."     # default: none
#   VOLUMES="/ /home"     # default: all from df -P
#   TIMEOUT=5

TIMEOUT=${TIMEOUT:-5}
[ -n "$VOLUMES" ] || VOLUMES=$(df -P | awk 'NR>1{print $6}')

route_status() {
    if [ -z "$URLS" ]; then
        printf '{\n  "checks": [],\n  "summary":{"total":0,"ok":0}\n}\n'
        return
    fi
    {
        printf '{\n  "checks": [\n'
        first=1 okcnt=0 tot=0
        for u in $URLS; do
            tot=$((tot+1))
            res=$(curl -sS -m "$TIMEOUT" -o /dev/null -w '%{http_code} %{time_total}' "$u" 2>/dev/null) || res="000 0"
            code=${res%% *}; ttot=${res#* }
            case $code in 2*|3*) ok=true; okcnt=$((okcnt+1));; *) ok=false;; esac
            [ $first -eq 0 ] && printf ',\n'; first=0
            printf '    {"url":"%s","code":%s,"time_s":%s,"ok":%s}' "$u" "$code" "$ttot" "$ok"
        done
        printf '\n  ],\n  "summary":{"total":%s,"ok":%s}\n}\n' "$tot" "$okcnt"
    }
}

route_disk() {
    {
        printf '{\n  "volumes": [\n'
        first=1
        for v in $VOLUMES; do
	    # POSIX df -P: Filesystem 1K-blocks Used Available Capacity Mounted on
	    # shellcheck disable=SC2046
            set -- $(df -P "$v" 2>/dev/null | awk 'NR==2{print $2, $3, $4, $5, $6}')
            size=$1 used=$2 avail=$3 usep=$4 mnt=$5
            [ -z "$size" ] && continue
            [ $first -eq 0 ] && printf ',\n'; first=0
            printf '    {"mount":"%s","size_blocks":%s,"used":%s,"avail":%s,"use_percent":"%s"}' \
              "$mnt" "$size" "$used" "$avail" "$usep"
        done
        printf '\n  ]\n}\n'
    }
}

# --- read request & headers ---
IFS= read -r req || exit 0
cr=$(printf '\r')
while IFS= read -r line; do
  [ -z "$line" ] && break
  [ "$line" = "$cr" ] && break
done

tmp=$(mktemp) || exit 1
trap 'rm -f "$tmp"' EXIT INT HUP

case "$req" in
  "GET /status "*) route_status >"$tmp"; status='200 OK'; ctype='application/json' ;;
  "GET /disk "*)   route_disk   >"$tmp"; status='200 OK'; ctype='application/json' ;;
  *)               printf 'Not found\n' >"$tmp"; status='404 Not Found'; ctype='text/plain' ;;
esac

len=$(wc -c <"$tmp" | awk '{print $1}')
printf 'HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %s\r\nConnection: close\r\n\r\n' "$status" "$ctype" "$len"
cat "$tmp"

