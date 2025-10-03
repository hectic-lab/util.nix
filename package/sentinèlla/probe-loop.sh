#!/bin/dash

# router.sh — POSIX sh HTTP backend (for socat)
# usage: socat -T5 -t5 TCP-LISTEN:${port},reuseaddr,fork EXEC:"sh ${currentfile}"
# Routes:
#   GET /status  -> check $URLS (0/0 if unset)
#   GET /disk    -> check $VOLUMES (all if unset)
# Env:
#   URLS="http://..."     # default: none
#   VOLUMES="/ /home"     # default: all from df -P
#   TIMEOUT=5

base64() {
  local mod
  mod="${1:?}"
  
  case "$mod" in
    encode) 
      printf '%s' "${2:?}" | od -An -t u1 | tr -s ' ' | tr -d '\n' | awk '
        BEGIN {
          A="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        }
        function dec2bin(n,    r,len,pad) {
            if (n==0) return "00000000"
            while (n>0) {
                r = (n%2) r
                n = int(n/2)
            }
            return sprintf("%08s", r)
        }
        function bin2dec(s,    i,d,r) {
            r=0
            for(i=1;i<=length(s);i++) {
                d=substr(s,i,1)
                r = r*2 + d
            }
            return r
        }
        function buildbin(t,    r) {
          for(i=1;i<=NF;i+=1) {
            #printf("%s | %s\n", dec2bin($i), $i)
            r = sprintf("%s%s", r, dec2bin($i))
          }
          return r
        }
        function base64(b,    r,c) {
          for(i=1;i<=length(b);i+=6) {
            #printf("%s | %s\n", substr(b,i,6), bin2dec(substr(b,i,6)))
            c = substr(A, bin2dec(substr(b,i,6))+1, 1)
            r = sprintf("%s%s", r, c)
          }
          return r
        }
        {  
          b=buildbin($1)
          l=length(b)
	  lack = (6 - l % 6) % 6
          b = sprintf("%s%0*d", b, lack, 0)
	  r = base64(b)
	  print lack
	  for(i=1;i<=lack/2;i+=1) {
	    r = sprintf("%s=", r)
          }
          print r
        }
      '
        ;;
    decode) 
      printf '%b\n' "$(printf '%s' "${2:?}" | awk ' BEGIN {
          A="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        }
        function dec2bin(n,    r,len,pad) {
            if (n==0) return "000000"
            while (n>0) {
                r = (n%2) r
                n = int(n/2)
            }
            r = sprintf("%6s", r)
            gsub(/ /,"0",r)
            return r
        }
        {
          for(i=1;i<=length($1);i+=1) {
	    b=sprintf("%s%s", b, dec2bin(index(A, substr($1,i,1))-1))
          }
          for(i=1; i<=length(b); i+=8){
            n=0
            for(j=0;j<8;j++) n = n*2 + (substr(b,i+j,1)=="1")
            printf "\\x%02X", n
          }
        }
      ')"
        ;;
  esac
}

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

require_auth=false
[ -n "$USER" ] && [ -n "$PASS" ] && require_auth=true

# --- read request & headers ---
IFS= read -r req || exit 0
cr=$(printf '\r')
while IFS= read -r line; do
  [ -z "$line" ] && break
  [ "$line" = "$cr" ] && break
  case "$line" in
    "Authorization: Basic "*) 
        tok=${line#Authorization: Basic }
        tok=$(printf '%s' "$tok" | tr -d '\r\n')
        expect=$(base64 encode "$USER:$PASS")
        [ "$tok" = "$expect" ] && auth_ok=true
        ;;
  esac
done

# --- auth gate ---
unauth() {
  body='{"error":"unauthorized"}'
  len=$(printf '%s' "$body" | wc -c | awk '{print $1}')
  printf 'HTTP/1.1 401 Unauthorized\r\n'
  printf 'Content-Type: application/json\r\n'
  printf 'Content-Length: %s\r\n' "$len"
  printf 'WWW-Authenticate: Basic realm="minimal", charset="UTF-8"\r\n'
  printf 'Connection: close\r\n\r\n'
  printf '%s' "$body"
}

if $require_auth && ! $auth_ok; then
  unauth
  exit 0
fi

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
