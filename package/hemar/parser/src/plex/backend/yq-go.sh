#!/bin/dash

PLEX_TEMP="$(mktemp -d)"
trap 'rm -rf $PLEX_TEMP' EXIT

#plex_set(name, key, value)
plex_set() {
    local plexfile key val
    plexfile="${PLEX_TEMP:?}/${1:?}.json" key="${2:?}" val="${3:?}"

    touch "$plexfile"

    yq -i ".$key = \"$val\"" "$plexfile" 
}

#plex_child(name, key)
plex_child() {
    plex_fetch "${1:?}" "${2:?}"
}

#plex_val(name, key)
plex_val() {
    plex_fetch "${1:?}" "${2:?}"
}

#plex_val(name, key)
plex_fetch() {
    local plexfile key
    plexfile="${PLEX_TEMP:?}/${1:?}.json" key="${2:?}"

    yq -r ".$key" "$plexfile" 
}

#plex_push(name, prefix, val)
plex_push() {
  local plexfile prefix val
  plexfile="${PLEX_TEMP:?}/${1:?}.json" prefix="${2:?}" val="${3:?}"

  yq -i ".$prefix += [\"$val\"]" "$plexfile" 
}
