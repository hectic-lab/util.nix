#!/bin/dash

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
        for(i=1;i<=lack;i+=1) {
          b = sprintf("%s0", b)
        }
        r = base64(b)
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
