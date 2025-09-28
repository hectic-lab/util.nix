#!/bin/dash

# 0 - text
# 1 - deside tag type
# 2 - interpolation
# 3 - section
# 4 - include
# 5 - compute
STAGE=0
STAGE_BUFFER="$(mktemp)"
open_tag_flag=0

# data structure :)

# Type = 0..=5
#
# Text = string            # just a text body
#
# Interpolation = string   # path to variable 
#
# Include = string         # path to include data
#
# Section = {
#   v = string      # item variable name for loop
#   p = string      # path to array for iteration
#   b = [Element]   # section body
#    
# }
#
# End = null
#
# Compute = {
#   l     = string  # programing language
#   b     = string  # function body
# }
#
# Element = {
#   t = Type        # element type
#   b = Text        # element body
#       | Interpolation 
#       | Section 
#       | End 
#       | Include 
#       | Compute 
# }
#
# Hemar = {
#    e = [Element]  # elements array
#}
# finds close pattern and store the char to the STAGE_BUFFER
find_close_pattern() {
  char="${1:?}"
  if   [ "${close_tag_flag:?}" -eq 0 ] && [ "$char" = ']' ]; then
    close_tag_flag=1
  elif [ "${close_tag_flag:?}" -eq 1 ] && [ "$char" = '}' ]; then
    close_tag_flag=0

    # removes first and last white spaces from the buffer
    sed -i 's/[[:space:]]$//g' "$STAGE_BUFFER"
    sed -i 's/^[[:space:]]//g' "$STAGE_BUFFER"
    
    # removes last char from buffer (]) is part of close pattern
    truncate -s -1 "$STAGE_BUFFER"
    return 0
  else
    printf '%s' "$char" >> "$STAGE_BUFFER"
  fi

  return 1
}

# finds open pattern and stores the char to the STAGE_BUFFER
find_open_pattern() {
  char="${1:?}"
  if   [ "${open_tag_flag:?}" -eq 0 ] && [ "$char" = '{' ]; then
    open_tag_flag=1
  elif [ "${open_tag_flag:?}" -eq 1 ] && [ "$char" = '[' ]; then
    open_tag_flag=0

    # removes last char from buffer ({) is part of open pattern
    truncate -s -1 "$STAGE_BUFFER"
    return 0
  else
    printf '%s' "$char" >> "$STAGE_BUFFER"
  fi

  return 1
}

parse() {
  char="$1"

  case "$STAGE" in
    0)
      if find_open_pattern "$char"; then
	plex_set "$data_pointer"''
        STAGE=1
      fi
      ;;
    1)
      if find_close_pattern "$char"; then
        STAGE=0
      fi
      ;;
    2)

      ;;
    3)
    
      ;;
    4)

      ;;
    *)

      ;;
  esac
}

# Using dd to read one character at a time
input=$(cat)
i=1
while :; do
    char=$(printf '%s' "$input" | dd bs=1 skip=$((i-1)) count=1 2>/dev/null)
    [ -z "$char" ] && break

    parse "$char"

    i=$((i+1))
done
