#!/bin/dash

log notice "running"

# segmented-path
#   segment
# Syntax scheme:
#
# hemar
#   elements
# 
# elements
#   element
#   element elements
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
#   '{[' ws for            ws ']}'
#   '{[' ws "done"         ws ']}'
#   '{[' ws '{['           ws ']}'
# 
# # loop tag
# for
#   "for" ws string ws "in" ws path
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
#   '['     digit           ']'
#   '['     onenine digits  ']'
#   '[' '-' onenine         ']'
#   '[' '-' onenine digits  ']'
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
#   '0020' . '10FFFF' - '"' - '\' - '.' - '[' - ']' - '{' - '}'
#
# quoted-string
#   unquoted-character
#   unquoted-character string
# 
# quoted-character
#   '0000' . '10FFFF' - '"'
#   '"' '"'
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


# AST Plex:
#
# Type = 0..=5
#
# Text = string            # just a text body
#
# Interpolation = string   # path to variable 
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

log_buffers() {
  log debug "buff 1: $WHITE$(cat "$STAGE_BUFFER_1")"
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

buf_reset() {
  : > "$STAGE_BUFFER_1"

  CURRENT_STAGE_BUFFER="$STAGE_BUFFER_1"
}

STAGE_BUFFER_1="$(mktemp)"
CURRENT_STAGE_BUFFER=$STAGE_BUFFER_1
trap 'rm -f "$STAGE_BUFFER_1"' EXIT INT HUP
log debug "stage buffer 1: ${WHITE}$STAGE_BUFFER_1"

# json_escape(value) -> str
json_escape() {
  # TODO: escape functionality
  printf '%s' "${1}" | sed 's/"/\\"/g' 
}

# finds close pattern and store the char to the stage buffers separating by spaces
parse_tag() {
  local char="${1:?}"
  # NOTE: any return 1 - skip char, regular_char + return 1 - write char
  # TAG_seen_first_ws     - we've already handled the first whitespace after `{[...]`
  # TAG_in_ws_run      - we’re currently in a run of whitespace chars
  # TAG_pending_close  - we saw `]` and are checking if the next char is `}`


  write_char() {
    [ ${TAG_next_argument_redgect+x} ] && {
      log error "too many argument for tag type $WHITE${TAG_type:?}$NC on $WHITE$LINE_N$NC:$WHITE$CHAR_N$NC";
      exit 1;
    }
    [ ${TAG_in_ws_run+x} ] && { 
        unset TAG_in_ws_run
        if [ "${TAG_seen_first_ws+x}" ]; then
          case "${TAG_type:-unknown}" in
            unknown) finalize_first_arg ;;
            for) 
              # NOTE: 
	      # grammar: for i in key."subkey" ; so we know
              # 1st argument after `for` - string (name of variable)
              # 2nd                      - 'in'   (just keyword)
              # 3rd                      - path   (path to array in Model)
              case ${TAG_grammar_mode:-1} in
                string)
                ;;
                kw_in) 
                ;;
                path) 
                ;;
              esac
            ;;
            *) log panic 'unexpected TAG_type'; exit 13; ;;
          esac

          # NOTE: prepare to next argument
          buf_reset
        else
          TAG_seen_first_ws=1
        fi
    }
    printf '%s' "$1" >> "$CURRENT_STAGE_BUFFER"
  }

  if   [ ! "${TAG_pending_close+x}" ] && [ "$char" = ']' ]; then
    TAG_pending_close=1
    # NOTE: skip ']' but remember to check next char for a possible '}'
    return 1
  elif [ "${TAG_pending_close+x}" ]; then
    unset TAG_pending_close
    if [ "$char" = '}' ]; then
      # NOTE: found `]}` — finish bracket parsing
      return 0
    else
      # NOTE: `]` was not followed by `}`, so emit the `]` we skipped
      printf ']' >> "$CURRENT_STAGE_BUFFER"
    fi
  else
    is_ws "$char" && { TAG_in_ws_run=1; return 1; }
      
    # NOTE: this is after char's checked on ws
    # so if TAG_in_ws_run exists then this is first char in argument (just after ws)
    if [ "${TAG_in_ws_run+x}" ] && [ "$char" = '"' ]; then
      [ "${TAG_in_quoted_string+x}" ] && { log panic "TAG_in_quoted_string already true right after ws"; exit 13; }
      TAG_in_quoted_string=1
      return 1
    elif [ "${TAG_in_quoted_string+x}" ]; then
      if [ "$char" = '"' ]; then
        TAG_end_quote_pending=1
	return 1
      fi
    elif [ "${TAG_end_quote_pending+x}" ]; then
      case "$char" in
        '"') 
          # NOTE: just ignoring it, because it expected behavior
        ;;
        '.')
          TAG_grammar_mode=path
        ;;
        *)  log error "unexpected end of quote on $WHITE$LINE_N$NC:$WHITE$CHAR_N" ;;
      esac
    fi
  fi

  grammar_check "$char"
  write_char    "$char"

  return 1
}

finalize_first_arg() {
  case "$(cat "$CURRENT_STAGE_BUFFER")" in
    for)
      TAG_type='for'
      # NOTE: we know that next argument after `for` is string
      TAG_grammar_mode=string
      log error 'for unimplemented'
      exit 13
    ;;
    done)
      TAG_type='done'
      TAG_next_argument_redgect=1
      # NOTE: Do not save {[ done ]} to the AST becouse it is useless there
    ;;
    '{[')
      TAG_type='actual bracket'
      TAG_next_argument_redgect=1
      if yq -e "${AST_key}[-1].type == \"text\"" "$AST" > /dev/null; then
        yq -o j -i "${AST_key}[-1].value += \"{[\"" "$AST"
      else
        yq -o j -i "$AST_key += [{
          \"type\": \"text\",
          \"value\": \"{[\"
        }]" "$AST"
      fi
    ;;
    *)         # interpolation tag
      TAG_type='interpolation'
      TAG_next_argument_redgect=1
      buf=$(cat "$STAGE_BUFFER_1")
      yq -o j -i "$AST_key += [{
        \"type\": \"interpolation\",
        \"path\": \"$(json_escape "$buf")\"
      }]" "$AST"
    ;;
  esac
}

# TAG_grammar_mode=
# ? - uncknown  - when we start parse first word in a tag, we never know what the type it is
# 1 - path
# 2 - string
# 3 - keyword in

grammar_check() {
  local char="$1"
  case "${TAG_grammar_mode:-unknown}" in
    unknown) 
      # NOTE: we always know grammar mode but first argument
      # just regular parse as string or as path if seen unquoted '.'

      !! if we here find a path so it interpolation, sure?

      if ! [ "${TAG_in_quoted_string+x}" ]; then
        unquoted_string_grammar
      fi
    ;;
    path) 
      if ! [ "${TAG_in_quoted_string+x}" ]; then
        unquoted_string_grammar
      fi
    ;;
    string) 
      if ! [ "${TAG_in_quoted_string+x}" ]; then
        unquoted_string_grammar
      fi
    ;;
    kw_in) 
    ;;
    *) log panic 'unexpected TAG_grammar_mode'; exit 13; ;;
  esac
}

unquoted_string_grammar() {
  # shellcheck disable=SC1003
  case "$char" in
    '['|']'|'{'|'}'|'"'|'.'|'\')
      log error "not allowed character $WHITE$char$NC on $WHITE$LINE_N$NC:$WHITE$CHAR_N"
      log error "try to use quoted string"
    ;;
  esac
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
      if parse_tag "$char"; then
        log_buffers

        # zero-initialization

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

CHAR_N=1
LINE_N=1
#LINE_NUMBER=1
while :; do
    # read exactly 1 byte; preserve newlines
    if ! char="$(dd bs=1 count=1 2>/dev/null)"; then
        break
    fi

    # NOTE: if $char is empty, it because `dd` returned '\n' but `$(...)` 
    # removed it as trailing '\n', so I set $char as '\n' here
    [ -z "$char" ] && {
        LINE_N=$((LINE_N+1))
        char='
'
    }

    parse "${char:?}"

    CHAR_N=$((CHAR_N+1))
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
