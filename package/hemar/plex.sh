#!/bin/dash

#data_size="$(eval printf '%s' "\$$structname" | wc -c)"
#if [ "$data_size" -ge "$(getconf ARG_MAX)" ]; then
#    # TODO: handle large text
#    echo "Data too large for an environment variable"
#    exit 1
#fi

plex_set() {
    local structname key val regex base esc_key regex esc temp
    structname=$1 key=$2 val=$3

    # construct regex for ancestors
    regex="^$key="

    base=$key
    while expr "$base" : '.*\.' >/dev/null; do
        base=$(printf '%s\n' "$base" | sed 's/\.[^.]*$//')
        esc=$(printf '%s\n' "$base" | sed 's/\./\\./g')
        regex="$regex|^$esc="
    done

    # add descendants
    esc_key="$(printf '%s\n' "$key" | sed 's/\./\\./g')"
    regex="$regex|^${esc_key}\."

    # remove old
    # <plex>=$(printf '%s\n' "$<plex>" | grep -v -E "$regex")
    temp="$(eval "printf '%s\\n' \"\$$structname\"" | grep -v -E "$regex")"
    eval "$structname=\"\$temp\""

    # add new
    eval "$structname=\$(printf '%s\\n%s=%s\\n' \"\$$structname\" \"\$key\" \"\$val\")"
}

plex_child() {
    local structname prefix
    structname=$1 prefix=$2

    eval printf '%s\\n' \"\$"$structname"\" \
      | grep "^$prefix\." \
      | sed "s|^$prefix\.||"
}

plex_val() {
    local structname key
    structname=$1 key=$2
    eval printf '%s\n' \"\$"$structname"\" | grep "^$key=" | cut -d= -f2-
}

plex_fetch() {
    local structname key
    structname=$1 key=$2
    if eval printf '%s\\n' \"\$"$structname"\" | grep -q "^$key="; then
      eval printf '%s\\n' \"\$"$structname"\" | grep "^$key=" | cut -d= -f2-
    else
      eval printf '%s\\n' \"\$"$structname"\" | grep "^$key\." | sed "s|^$key\.||"
    fi
}

plex_push() {
  local structname prefix val max idx newidx kv
  structname=${1:?}
  prefix=${2:?}
  val=${3:?}

  # find max index
  max=0
  for kv in $(plex_fetch "$structname" "$prefix"); do
      idx=${kv%%=*}
      [ "$idx" -gt "$max" ] 2>/dev/null && max=$idx
  done

  newidx=$((max + 1))
  plex_set "$structname" "$prefix.$newidx" "$val"
}
