#!/bin/dash

PLEX_TEMP="$(mktemp -d)"

#plex_set(name, key, value)
plex_set() {
    local plexfile key val regex base esc_key esc
    plexfile="${PLEX_TEMP:?}${1:?}" key="${2:?}" val="${3:?}"

    find PLEX_
}

plex_child() {
    local plexfile key
    plexfile="${PLEX_TEMP:?}${1:?}" key="${2:?}"

    grep "^$key\." "" | sed "s|^$key\.||"
}

plex_val() {
    local plexfile key
    plexfile="${PLEX_TEMP:?}${1:?}" key="${2:?}"
    grep "^$key=" | cut -d= -f2- "$plexfile"
}

plex_fetch() {
    local plexfile key temp
    plexfile="${PLEX_TEMP:?}${1:?}" key="${2:?}"

    if temp="$(grep "^$key=" | cut -d= -f2- "$plexfile")"; then
      printf '%s' "$temp"
    else
      grep "^$key\." "" | sed "s|^$key\.||"
    fi
}

plex_push() {
  local plex prefix val max idx newidx kv
  plex="${1:?}" prefix="${2:?}" val="${3:?}"

  # find max index
  max=0
  for kv in $(plex_fetch "$plex" "$prefix"); do
      idx=${kv%%=*}
      [ "$idx" -gt "$max" ] 2>/dev/null && max=$idx
  done

  newidx=$((max + 1))
  plex_set "$plex" "$prefix.$newidx" "$val"
}
