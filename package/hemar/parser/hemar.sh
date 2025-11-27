#!/bin/dash

log notice "running"

# Syntax scheme:
#
# hemar
#   elements
# 
# elements
#   element
#   element ws elements
# 
# element
#   tag
#   text
# 
# text
#   text-item
#   text-item text
# 
# text-item
#   '0020' . '10FFFF' - '{'
#   nopatern
# 
# tag
#   '{[' ws path           ws ']}'
#   '{[' ws loop-statement ws ']}'
#   '{[' ws include-header ws ']}'
#   '{[' ws "end"          ws ']}'
#   '{[' ws function       ws ']}'
#   '{[' ws '{['           ws ']}'
# 
# # loop tag
# loop-statemant
#   "for" string "in" path
# 
# # include tag
# include-header
#   "include" path
# 
# # fucntion tag
# function
#   'compute' language function-body
#   'compute' - function-body
# 
# language
#   'dash'
#   'plpgsql'
# 
# function-body
#   ''
#   '0020' . '10FFFF', function-body
# 
# function-character
#   '0020' . '10FFFF' - ']'
#   ncpatern
# 
# # path
# path
#   '.'
#   segmented-path
# 
# segmented-path
#   segment
# Syntax scheme:
#
# hemar
#   elements
# 
# elements
#   element
#   element ws elements
# 
# element
#   tag
#   text
# 
# text
#   text-item
#   text-item text
# 
# text-item
#   '0020' . '10FFFF' - '{'
#   nopatern
# 
# tag
#   '{[' ws path           ws ']}'
#   '{[' ws loop-statement ws ']}'
#   '{[' ws include-header ws ']}'
#   '{[' ws "end"          ws ']}'
#   '{[' ws function       ws ']}'
#   '{[' ws '{['           ws ']}'
# 
# # loop tag
# loop-statemant
#   "for" string "in" path
# 
# # include tag
# include-header
#   "include" path
# 
# # fucntion tag
# function
#   'compute' language function-body
#   'compute' - function-body
# 
# language
#   'dash'
#   'plpgsql'
# 
# function-body
#   ''
#   '0020' . '10FFFF', function-body
# 
# function-character
#   '0020' . '10FFFF' - ']'
#   ncpatern
# 
# # path
# path
#   '.'
#   segmented-path
# 
# segmented-path
#   segment
#   segment '.' segmented-path
# 
# segment
#   string
#   index
# 
# index
#   '\'     digit
#   '\'     onenine digits
#   '\' '-' digit
#   '\' '-' onenine digits
# 
# # types
# string
#   unquoted-string
#   quoted-string
#
# unquoted-string
#   unquoted-character
#   unquoted-character quoted-string
#
# unquoted-character
#   '0020' . '10FFFF' - '"' - '\' - '.' - ws - ']'
#   ']' '0020' . '10FFFF' - '"' - '\' - '.' - ws - '}'
#
# quoted-string
#   unquoted-character
#   unquoted-character string
# 
# quoted-character
#   '0020' . '10FFFF' - '"' - '\'
#   '\' escape
# 
# escape
#   '"'
#   '\'
#   '/'
#   'b'
#   'f'
#   'n'
#   'r'
#   't'
#   'u' hex hex hex hex
# 
# hex
#   digit
#   'A' . 'F'
#   'a' . 'f'
# 
# digits
#   digit
#   digit digits
# 
# digit
#   '0'
#   onenine
# 
# onenine
#   '1' . '9'
# 
# # paterns
# ws
#   ''
#   '\x20' ws
#   '\x0a' ws
#   '\x0d' ws
#   '\x09' ws
# 
# nopatern
#   '{' '0020' . '10FFFF' - '['
# 
# segment
#   string
#   index
# 
# index
#   '\'     digit
#   '\'     onenine digits
#   '\' '-' digit
#   '\' '-' onenine digits
# 
# # types
# string
#   unquoted-string
#   quoted-string
#
# unquoted-string
#   unquoted-character
#   unquoted-character quoted-string
#
# unquoted-character
#   '0020' . '10FFFF' - '"' - '\' - '.' - ws - ']'
#   ']' '0020' . '10FFFF' - '"' - '\' - '.' - ws - '}'
#
# quoted-string
#   unquoted-character
#   unquoted-character string
# 
# quoted-character
#   '0020' . '10FFFF' - '"' - '\'
#   '\' escape
#   ncpatern
# 
# escape
#   '"'
#   '\'
#   '/'
#   'b'
#   'f'
#   'n'
#   'r'
#   't'
#   'u' hex hex hex hex
# 
# hex
#   digit
#   'A' . 'F'
#   'a' . 'f'
# 
# digits
#   digit
#   digit digits
# 
# digit
#   '0'
#   onenine
# 
# onenine
#   '1' . '9'
# 
# # paterns
# ws
#   ''
#   '\x20' ws
#   '\x0a' ws
#   '\x0d' ws
#   '\x09' ws


# AST Plex:
#
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
# AbstarctSyntaxTree (ATS) = {
#    e = [Element]  # elements array
# }
AST=$(mktemp)
AST_key='.'
trap 'rm -f "$AST"' EXIT INT HUP

yq -o j -i '.' "$AST"

log debug "AST path: ${WHITE}${AST}"

# 0 - text
# 1 - deside tag type
# 2 - interpolation
# 3 - section
# 4 - include
# 5 - compute
STAGE=0

# is_ws(char) -> bool
is_ws() {
  ord=$(printf '%d' "'$1")
  case $ord in
    32|10|13|9) # <-> \x20 | \x0a | \x0d | \x09 <-> space | \n | \r | \t 
      return 0
    ;;            
  esac            
  return 1
}

# remove_last_double_quote(text) -> text
remove_last_double_quote() {
  printf '%s' "$1" | sed 's/\(.*\)"\(.*\)/\1\2/'
}

#buf_read(buf?) -> text
buf_read() {
  local buf
  if [ ${1+x} ]; then
    buf=${1}
  else
    buf=${CURRENT_STAGE_BUFFER}
  fi

  cat "$buf"
}

#buf_next()
buf_next() {
  case "$CURRENT_STAGE_BUFFER" in
    "$STAGE_BUFFER_1")
      CURRENT_STAGE_BUFFER="$STAGE_BUFFER_2"
    ;;
    "$STAGE_BUFFER_2")
      CURRENT_STAGE_BUFFER="$STAGE_BUFFER_3"
    ;;
    "$STAGE_BUFFER_3")
      CURRENT_STAGE_BUFFER="$STAGE_BUFFER_4"
    ;;
    "$STAGE_BUFFER_4")
      CURRENT_STAGE_BUFFER="$STAGE_BUFFER_1"
    ;;
  esac
}

buf_reset() {
  : > "$STAGE_BUFFER_1"
  : > "$STAGE_BUFFER_2"
  : > "$STAGE_BUFFER_3"
  : > "$STAGE_BUFFER_4"

  CURRENT_STAGE_BUFFER="$STAGE_BUFFER_1"
}

STAGE_BUFFER_1="$(mktemp)"
STAGE_BUFFER_2="$(mktemp)"
STAGE_BUFFER_3="$(mktemp)"
STAGE_BUFFER_4="$(mktemp)"
CURRENT_STAGE_BUFFER=$STAGE_BUFFER_1
trap 'rm -f "$STAGE_BUFFER_1" "$STAGE_BUFFER_2" "$STAGE_BUFFER_3" "$STAGE_BUFFER_4"' EXIT INT HUP
log debug "stage buffer 1: ${WHITE}$STAGE_BUFFER_1"
log debug "stage buffer 2: ${WHITE}$STAGE_BUFFER_2"
log debug "stage buffer 3: ${WHITE}$STAGE_BUFFER_3"
log debug "stage buffer 4: ${WHITE}$STAGE_BUFFER_4"

# json_escape(value) -> str
json_escape() {
  # TODO: escape functionality
  printf '%s' "${1}" | sed 's/"/\\"/g' 
}

# finds close pattern and store the char to the stage buffers separating by spaces
find_close_pattern() {
  local buf char="${1:?}"

  regular_char() {
    [ ${TAG_ws_started+x} ] && { 
	unset TAG_ws_started
        if [ "${TAG_first_ws_handled+x}" ]; then
	  buf_next
	else
	  TAG_first_ws_handled=1
	fi
    }
    printf '%s' "$1" >> "$CURRENT_STAGE_BUFFER"
  }

  if   [ ! "${TAG_close_tag_flag+x}" ] && [ "$char" = ']' ]; then
    TAG_close_tag_flag=1
  elif [ "${TAG_close_tag_flag+x}" ]; then
    unset TAG_close_tag_flag
    if [ "$char" = '}' ]; then

      log debug "cur buf: $WHITE$(cat "$STAGE_BUFFER_1")"
      # removes first and last white spaces from the buffer
      sed -i 's/[[:space:]]$//g' "$CURRENT_STAGE_BUFFER"
      sed -i 's/^[[:space:]]//g' "$CURRENT_STAGE_BUFFER"

      return 0
    else
      regular_char ']'"$char"
    fi
  else
    # shellcheck disable=SC1003
    case "$char" in
      '"')
	if [ "${TAG_escape_flag+x}" ]; then
          unset TAG_escape_flag
	else
          if [ ${TAG_double_quote_flag+x} ]; then
            unset TAG_double_quote_flag
            return 1
          else 
            TAG_double_quote_flag=1
            return 1
          fi
	fi
      ;;
      '\')
        if [ "${TAG_escape_flag+x}" ]; then
          unset TAG_escape_flag
        else
          TAG_escape_flag=1
          return 1
        fi
      ;;
      *)
        if [ "${TAG_escape_flag+x}" ]; then
          if is_ws "$char"; then
	    unset TAG_escape_flag
	  else 
	    log error "unexpected char \`$char\` after escape symbol"
	    exit 1
	  fi
        elif is_ws "$char" && ! [ "${TAG_double_quote_flag+x}" ]; then 
          TAG_ws_started=1
	  return 1
        fi
      ;;
    esac

    regular_char "$char"
  fi

  return 1
}

# finds open pattern and stores the char to the STAGE_BUFFER_1
find_open_pattern() {
  local char="${1:?}"
  if   [ ! "${open_tag_flag+x}" ] && [ "$char" = '{' ]; then
    open_tag_flag=1
  elif [ "${open_tag_flag+x}" ]; then
    unset open_tag_flag
    if [ "$char" = '[' ]; then
      return 0
    else
      printf '{%s' "$char" >> "$CURRENT_STAGE_BUFFER"
    fi
  else
    printf '%s' "$char" >> "$CURRENT_STAGE_BUFFER"
  fi

  return 1
}

parse() {
  char="$1"

  case "$STAGE" in
    # Text Stage - save char in STAGE_BUFFER_1 until next tag opens
    0)
      if find_open_pattern "$char"; then
	log debug "open pattern founded"
	buf=$(cat "$CURRENT_STAGE_BUFFER")
        yq -o j -i "$AST_key += [{
	  \"type\": \"text\",
	  \"value\": \"$(json_escape "$buf")\"
        }]" "$AST"

        buf_reset
        STAGE=1
      fi
    ;;
    1)
      if find_close_pattern "$char"; then
	case "$(cat "$STAGE_BUFFER_1")" in
	  compute)
	    log error 'compute unimplemented'
	  ;;
	  include)
	    log error 'include unimplemented'
	  ;;
	  for)
	    path=$STAGE_BUFFER_2

	    log error 'for unimplemented'
	  ;;
          end)
	    log error 'end unimplemented'
	  ;;
          '{[')
            yq -o j -i "$AST_key += [{
	      \"type\": \"text\",
	      \"value\": \"{[\"
            }]" "$AST"
	  ;;
          *)         # interpolation tag
	    buf=$(cat "$STAGE_BUFFER_1")
            yq -o j -i "$AST_key += [{
	      \"type\": \"interpolation\",
	      \"path\": \"$(json_escape "$buf")\"
            }]" "$AST"
	  ;;
	esac

        # zero-initialization
        unset TAG_ws_started TAG_double_quote_flag TAG_escape_flag TAG_first_ws_handled TAG_close_tag_flag

	buf_reset
	STAGE=1
      fi
    ;;
    2)
        
    ;;
    3)
    
    ;;
    4)

    ;;
    *)
      log error "error: ${WHITE}impossible stage"
      exit 13
    ;;
  esac
}

while [ $# -gt 0 ]; do
  case $1 in
    -c|--compact-output)
      OUTPUT_ARGS="${OUTPUT_ARGS+$OUTPUT_ARGS }-I=0"
      shift
    ;;
    --*|-*)
      log error "argument $1 does not exists"
      exit 9
    ;;
    *)
      log error "subcommand $1 does not exists"
      exit 9
    ;;
  esac
done

# Using dd to read one character at a time
input=$(cat)
i=1
while :; do
    #log trace "loop"
    char=$(printf '%s' "$input" | dd bs=1 skip=$((i-1)) count=1 2>/dev/null)
    [ -z "$char" ] && break

    parse "$char"

    i=$((i+1))
done

# finish TEXT tag if file ends on it
if [ "$STAGE" -eq 0 ]; then
  if [ "${open_tag_flag+x}" ]; then
    unset open_tag_flag
    printf '{' >> "$STAGE_BUFFER_1"
  fi
    
  buf=$(cat "$STAGE_BUFFER_1")
  yq -o j -i "$AST_key += [{
    \"type\": \"text\",
    \"value\": \"$(json_escape "$buf")\"
  }]" "$AST"
fi

# return the output
# shellcheck disable=SC2086
yq ${OUTPUT_ARGS:-} -o j "$AST"
