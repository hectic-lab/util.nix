# Wrapper for pg_dump with url option
{ writeShellScriptBin, postgresql, ... }:
writeShellScriptBin "wpg_dupmall" /* */ ''
#!/bin/sh

while [ $# -gt 0 ]; do
  case "$1" in
    --url=*)
      url="''${1#--url=}"
      shift
      ;;
    --url)
      url="$2"
      shift 2
      ;;
    *)
      args="$args $1"
      shift
      ;;
  esac
done

if [ -n "$url" ]; then
  user=$(echo "$url" | sed -E 's|.*://([^:]+):.*@.*|\1|')
  pass=$(echo "$url" | sed -E 's|.*://[^:]+:([^@]+)@.*|\1|')
  host=$(echo "$url" | sed -E 's|.*@([^:/]+):.*|\1|')
  port=$(echo "$url" | sed -E 's|.*:([0-9]+)/?.*|\1|')
  export PGPASSWORD="$pass"
  exec ${postgresql}/bin/pg_dump -h "$host" -p "$port" -U "$user" $args
else
  exec ${postgresql}/bin/pg_dump $args
fi
''
