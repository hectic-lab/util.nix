#!/bin/dash

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


# AST Structure:
#
# The parser outputs a JSON array of elements directly (not wrapped in an object).
#
# Element types (currently implemented):
#
# Text = {
#   "type": "text",
#   "value": string    # text content
# }
#
# Interpolation = {
#   "type": "interpolation",
#   "path": [PathSegment, ...]  # structured path to variable in data model
# }
#
# PathSegment = {
#   "type": "root"              # root path: "."
# } | {
#   "type": "key",
#   "key": string              # key name (can contain spaces if quoted)
# } | {
#   "type": "index",
#   "index": number            # array index (can be negative)
# }
#
# Element types (planned for MVP):
#
# Section = {
#   "type": "section",
#   "variable": string    # item variable name for loop
#   "path": string        # path to array for iteration
#   "body": [Element]    # section body (nested elements)
# }
#
# Element types (planned for future, not MVP):
#
# Include = {
#   "type": "include",
#   "path": string     # path to template file to include
# }
#
# Compute = {
#   "type": "compute",
#   "language": string  # programming language (dash, plpgsql, etc.)
#   "body": string      # function body
# }
#
# AbstractSyntaxTree = [Element, ...]  # array of elements

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

# json_escape(value) -> str
json_escape() {
  local input="${1}"
  local output=""
  local char hex
  
  while [ -n "$input" ]; do
    char="${input%"${input#?}"}"  # Get first character
    input="${input#?}"            # Remove first character
    
    hex=$(printf '%d' "'$char")
    
    case "$hex" in
      34)  output="${output}\\\"" ;;  # "
      92)  output="${output}\\\\" ;;  # \
      10)  output="${output}\\n" ;;   # \n (newline)
      13)  output="${output}\\r" ;;   # \r (carriage return)
      9)   output="${output}\\t" ;;   # \t (tab)
      8)   output="${output}\\b" ;;   # \b (backspace)
      12)  output="${output}\\f" ;;   # \f (form feed)
      *)
        # NOTE(yukkop): escape control characters if they are not in the range 0x20-0x7E
        if [ "$hex" -lt 32 ]; then
          output="${output}\\u$(printf '%04x' "$hex")"
        else
          output="${output}${char}"
        fi
        ;;
    esac
  done
  
  printf '%s' "$output"
}

# finds close pattern and store the char to the stage buffers separating by spaces
parse_tag() {
  local char="${1:?}"
  # NOTE: any return 1    - skip char, regular_char + return 1 - write char
  # TAG_seen_first_ws     - we've already handled the first whitespace after `{[...]`
  # TAG_in_ws_run         - we’re currently in a run of whitespace chars
  # TAG_pending_close     - we saw `]` and are checking if the next char is `}`

  string_grammar() {
    if [ "${TAG_in_quoted_string+x}" ]; then
      if [ "${TAG_end_quote_pending+x}" ]; then
        case "$char" in
          '"') 
            # Escaped quote: "" -> write single quote and continue in quoted string
            unset TAG_end_quote_pending
            printf '"' >> "$CURRENT_STAGE_BUFFER"
            return 1
          ;;
          '.')
            # Closing quote followed by dot: exit quoted string
            unset TAG_end_quote_pending
            unset TAG_in_quoted_string
            # In path mode or transitioning to path mode, write the dot as separator
            # Otherwise, set TAG_dote to switch to path mode on next char
            if [ "${TAG_grammar_mode:-unknown}" = "path" ]; then
              # Already in path mode, write the dot
              return 0  # Allow write_char to write the dot
            else
              # Will transition to path mode, write the dot now
              TAG_dote=1
              return 0  # Write the dot, will switch to path mode on next char
            fi
          ;;
          ']'|'}')
            # Closing quote followed by bracket: exit quoted string, let bracket be handled
            unset TAG_end_quote_pending
            unset TAG_in_quoted_string
            return 1
          ;;
          *)
            if is_ws "$char"; then
              # Closing quote followed by whitespace: exit quoted string
              unset TAG_end_quote_pending
              unset TAG_in_quoted_string
              TAG_in_ws_run=1
              return 1
            else
              log error "unexpected character $WHITE$char$NC after closing quote on $WHITE$LINE_N$NC:$WHITE$CHAR_N"
              log error "expected: whitespace, dot, or end of tag"
              exit 1
            fi
          ;;
        esac
      elif [ "$char" = '"' ]; then
        # We see a quote inside quoted string: might be closing or escaped
        TAG_end_quote_pending=1
        return 1
      else
        # Inside quoted string, all other chars are allowed (will be written by write_char)
        return 0
      fi
    else
      # Not in quoted string: validate unquoted characters
      # shellcheck disable=SC1003
      case "$char" in
        '}'|'"'|'\')
          log error "not allowed character $WHITE$char$NC on $WHITE$LINE_N$NC:$WHITE$CHAR_N"
          log error "try to use quoted string"
          exit 1
        ;;
        ']')
          # `]` is allowed in paths for index notation like [0], [-1]
          # The bracket closing logic above handles tag closing `]}`
          return 0  # Allow write_char to write the `]`
        ;;
        '[')
          # `[` is allowed in paths for index notation
          return 0  # Allow write_char to write the `[`
        ;;
        '.')
          # Dot handling: if buffer is empty, write dot (root path), otherwise it's a separator
          if [ ! -s "$CURRENT_STAGE_BUFFER" ]; then
            # Empty buffer + dot = root path, write the dot
            return 0  # Allow write_char to write the dot
          else
            # Non-empty buffer + dot = separator
            TAG_dote=1
            return 1  # Skip the dot, it's a separator
          fi
        ;;
      esac
      return 0
    fi
  }

  write_char() {
    [ ${TAG_next_argument_redgect+x} ] && {
      log error "too many argument for tag type $WHITE${TAG_type:?}$NC on $WHITE$LINE_N$NC:$WHITE$CHAR_N$NC";
      exit 1;
    }
    [ ${TAG_in_ws_run+x} ] && { 
        unset TAG_in_ws_run
        if [ "${TAG_seen_first_ws+x}" ]; then
          log trace "tag in ws -> type: \`${TAG_type:-}\`"
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

  # Check if we need to exit quoted string due to pending quote followed by bracket
  if [ "${TAG_in_quoted_string+x}" ] && [ "${TAG_end_quote_pending+x}" ]; then
    if [ "$char" = ']' ] || [ "$char" = '}' ]; then
      # Closing quote followed by bracket: exit quoted string, handle bracket
      unset TAG_end_quote_pending
      unset TAG_in_quoted_string
      # Fall through to bracket handling
    fi
  fi

  if ! [ "${TAG_in_quoted_string+x}" ]; then 
    if   [ ! "${TAG_pending_close+x}" ] && [ "$char" = ']' ]; then
      # Always check for tag closing `]}` by setting pending and checking next char
      # If next char is not `}`, the `]` was part of path (index notation) and will be written
      TAG_pending_close=1
      return 1
    elif [ "${TAG_pending_close+x}" ]; then
      unset TAG_pending_close
      if [ "$char" = '}' ]; then
        finish

        # NOTE: found `]}` — finish bracket parsing
        return 0
      else
        # NOTE: `]` was not followed by `}`, so it was part of path (index notation)
        # Emit the `]` we skipped, then process current char
        printf ']' >> "$CURRENT_STAGE_BUFFER"
        # Current char might be another `]` (tag closing) or part of path
        # Fall through to process it (might hit the `]` case again if it's another `]`)
        if [ "$char" = ']' ]; then
          # This is another `]`, might be tag closing - check again
          TAG_pending_close=1
          return 1
        fi
        # Otherwise, continue processing the char normally
      fi
    else
      is_ws "$char" && { TAG_in_ws_run=1; return 1; }
    fi
  fi

  # If TAG_dote is set in unknown mode (from exiting quoted string), switch to path mode
  if [ "${TAG_grammar_mode:-unknown}" = "unknown" ] && [ ${TAG_dote+x} ]; then
    TAG_grammar_mode=path
    unset TAG_dote
  fi

  case "${TAG_grammar_mode:-unknown}" in
    unknown) 
      # NOTE: we always know grammar mode but first argument
      # just regular parse as string or as path if seen unquoted '.'
      
      # NOTE: this is after char's checked on ws
      # Quote is allowed: at start of tag (empty buffer), after whitespace, or after dot
      if [ "$char" = '"' ]; then
        # Check if we're at start (empty buffer), after whitespace, or at tag start
        if [ ! -s "$CURRENT_STAGE_BUFFER" ] || [ "${TAG_in_ws_run+x}" ]; then
          [ "${TAG_in_quoted_string+x}" ] && { log panic "TAG_in_quoted_string already true"; exit 13; }
          TAG_in_quoted_string=1
          # Track if path started with a quote (for distinguishing root vs quoted ".")
          if [ ! -s "$CURRENT_STAGE_BUFFER" ]; then
            TAG_path_was_quoted=1
          fi
          return 1
        fi
        # Quote in middle of unquoted string - let string_grammar reject it
      fi

      if ! string_grammar; then
        # string_grammar returned 1 (skip char)
        # Check if it was because of a dot - if so, write it and switch to path mode
        if [ ${TAG_dote+x} ]; then
          # Dot was seen - write it to buffer and switch to path mode
          printf '.' >> "$CURRENT_STAGE_BUFFER"
          TAG_grammar_mode=path
          unset TAG_dote
        fi
        return 1
      fi
      # string_grammar returned 0 (write char) - check if dot was seen
      if [ ${TAG_dote+x} ]; then
        # Dot was seen - write it to buffer and switch to path mode
        printf '.' >> "$CURRENT_STAGE_BUFFER"
        TAG_grammar_mode=path
        unset TAG_dote
      fi
    ;;
    path) 
      # In path mode, dots are separators but need to be in buffer for parse_path() to split
      if [ "$char" = '.' ] && [ ! "${TAG_in_quoted_string+x}" ]; then
        # Write dot to buffer as separator (parse_path will split on it)
        # Write it directly and skip string_grammar (which would try to skip it)
        printf '.' >> "$CURRENT_STAGE_BUFFER"
        return 1  # Skip further processing
      fi

      # Quote is allowed: after whitespace, after dot, or if buffer ends with dot (just wrote separator)
      if [ "$char" = '"' ]; then
        local buffer_content
        buffer_content=$(cat "$CURRENT_STAGE_BUFFER" 2>/dev/null || true)
        local last_char="${buffer_content#"${buffer_content%?}"}"  # Get last char
        local after_dot=0
        [ "$last_char" = '.' ] && after_dot=1
        
        if [ "${TAG_in_ws_run+x}" ] || [ "${TAG_dote+x}" ] || [ ! -s "$CURRENT_STAGE_BUFFER" ] || [ "$after_dot" = "1" ]; then
          [ "${TAG_in_quoted_string+x}" ] && { log panic "TAG_in_quoted_string already true"; exit 13; }
          [ "${TAG_dote+x}" ] && unset TAG_dote
          TAG_in_quoted_string=1
          # Track if this segment started with a quote
          if [ ! -s "$CURRENT_STAGE_BUFFER" ] || [ "${TAG_dote+x}" ] || [ "$after_dot" = "1" ]; then
            TAG_path_was_quoted=1
          fi
          return 1
        fi
        # Quote in middle of unquoted string - let string_grammar reject it
      fi

      [ "${TAG_dote+x}" ] && unset TAG_dote
        

      string_grammar || return 1
    ;;
    string) 
      # Quote is allowed: after whitespace or at segment start
      if [ "$char" = '"' ]; then
        if [ "${TAG_in_ws_run+x}" ] || [ ! -s "$CURRENT_STAGE_BUFFER" ]; then
          [ "${TAG_in_quoted_string+x}" ] && { log panic "TAG_in_quoted_string already true"; exit 13; }
          TAG_in_quoted_string=1
          return 1
        fi
        # Quote in middle of unquoted string - let string_grammar reject it
      fi

      string_grammar || return 1
      if [ ${TAG_dote+x} ]; then
        log error ". not allowed, use quote to escape it; on $WHITE$LINE_N$NC:$WHITE$CHAR_N$NC"
      fi
    ;;
    kw_in) 
    ;;
    *) log panic 'unexpected TAG_grammar_mode'; exit 13; ;;
  esac
  write_char    "$char"

  return 1
}

finish() {
  case "${TAG_type:-unknown}" in
    unknown) 
      finish_interpolation_tag
    ;;
    done)
      finish_done_tag
    ;;
    '{[')
      finish_bracket_tag
    ;;
    for) ;;
    *) log panic 'unexpected TAG_type on finish'; exit 13; ;;
  esac
}

finalize_first_arg() {
  log trace "finalize first arg"
  log trace "buffer: $(cat "$CURRENT_STAGE_BUFFER")"
  case "$(cat "$CURRENT_STAGE_BUFFER")" in
    for)
      TAG_type='for'
      # NOTE: we know that next argument after `for` is string
      TAG_grammar_mode=string
      log error 'for unimplemented'
      exit 13
    ;;
    done)
      finish_done_tag
    ;;
    '{[')
      finish_bracket_tag
    ;;
    *)         # interpolation tag
      finish_interpolation_tag
    ;;
  esac
}

finish_done_tag() {
  TAG_type='done'
  TAG_next_argument_redgect=1
  # NOTE: Do not save {[ done ]} to the AST becouse it is useless there
}

finish_bracket_tag() {
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
}

# parse_path(path_string, was_quoted?) -> JSON array of path segments
parse_path() {
  local path_str="${1}"
  local was_quoted="${2:-0}"
  local segments_file
  segments_file=$(mktemp)
  yq -o j -n "[]" > "$segments_file"
  
  # Handle root path - only if it's unquoted
  if [ "$path_str" = "." ] && [ "$was_quoted" != "1" ]; then
    yq -o j -i ". += [{\"type\":\"root\"}]" "$segments_file"
    local result
    result=$(cat "$segments_file")
    rm -f "$segments_file"
    printf '%s' "$result"
    return 0
  fi
  
  local current_segment=""
  local in_index=0
  local index_str=""
  local char
  
  # Process each character
  while [ -n "$path_str" ]; do
    char="${path_str%"${path_str#?}"}"  # Get first character
    path_str="${path_str#?}"              # Remove first character
    
    case "$char" in
      '[')
        # Start of index
        if [ -n "$current_segment" ]; then
          # Add current segment as key
          yq -o j -i ". += [{\"type\":\"key\",\"key\":\"$(json_escape "$current_segment")\"}]" "$segments_file"
          current_segment=""
        fi
        in_index=1
        index_str=""
        ;;
      ']')
        # End of index
        if [ "$in_index" -eq 1 ]; then
          # Parse index (can be negative)
          if [ -n "$index_str" ]; then
            yq -o j -i ". += [{\"type\":\"index\",\"index\":$index_str}]" "$segments_file"
          fi
          in_index=0
          index_str=""
        else
          # ] without [ - treat as part of segment
          current_segment="${current_segment}]"
        fi
        ;;
      '.')
        if [ "$in_index" -eq 1 ]; then
          # Dot inside index - invalid, but treat as part of index string
          index_str="${index_str}."
        elif [ -n "$current_segment" ]; then
          # Dot separator - add current segment as key
          yq -o j -i ". += [{\"type\":\"key\",\"key\":\"$(json_escape "$current_segment")\"}]" "$segments_file"
          current_segment=""
        else
          # Dot at start of segment
          # Check if we already have segments - if so, this is a separator, skip it
          local segment_count
          segment_count=$(yq '. | length' "$segments_file" 2>/dev/null || echo "0")
          if [ "$segment_count" -gt 0 ]; then
            # We have segments already, this dot is a separator - skip it
            :
          else
            # No segments yet - treat as part of key name (from quoted string like ".key")
            current_segment="."
          fi
        fi
        ;;
      *)
        if [ "$in_index" -eq 1 ]; then
          index_str="${index_str}${char}"
        else
          current_segment="${current_segment}${char}"
        fi
        ;;
    esac
  done
  
  # Add remaining segment if any
  if [ -n "$current_segment" ]; then
    yq -o j -i ". += [{\"type\":\"key\",\"key\":\"$(json_escape "$current_segment")\"}]" "$segments_file"
  fi
  
  local result
  result=$(cat "$segments_file")
  rm -f "$segments_file"
  printf '%s' "$result"
}

finish_interpolation_tag() {
  log trace 'finish interpolation tag'
  TAG_type='interpolation'
  TAG_next_argument_redgect=1
  buf=$(cat "$STAGE_BUFFER_1")
  was_quoted="${TAG_path_was_quoted:-0}"
  path_segments=$(parse_path "$buf" "$was_quoted")
  yq -o j -i "$AST_key += [{
    \"type\": \"interpolation\",
    \"path\": $path_segments
  }]" "$AST"
  unset TAG_path_was_quoted
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
        log trace "open pattern founded"
        buf=$(cat "$CURRENT_STAGE_BUFFER")
        # NOTE: Only add text element if buffer is not empty
        if [ -n "$buf" ]; then
          yq -o j -i "$AST_key += [{
            \"type\": \"text\",
            \"value\": \"$(json_escape "$buf")\"
          }]" "$AST"
        fi

        buf_reset
        STAGE=1
      fi
    ;;
    1)
      if parse_tag "$char"; then
        log_buffers

        # zero-initialization
        unset TAG_seen_first_ws TAG_in_ws_run TAG_pending_close TAG_type TAG_next_argument_redgect TAG_grammar_mode TAG_in_quoted_string TAG_dote TAG_path_was_quoted

        buf_reset
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
      log error "error: ${WHITE}impossible stage"
      exit 13
    ;;
  esac
}


if [ -z "${AS_LIBRARY+x}" ]; then
  log notice "running"

  AST=$(mktemp)
  yq -o j -i "[]" "$AST"
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

  STAGE_BUFFER_1="$(mktemp)"
  CURRENT_STAGE_BUFFER=$STAGE_BUFFER_1
  trap 'rm -f "$STAGE_BUFFER_1"' EXIT INT HUP
  log debug "stage buffer 1: ${WHITE}$STAGE_BUFFER_1"

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

  while :; do
      hex="$(dd bs=1 count=1 2>/dev/null | od -An -t u1)"

      [ -z "$hex" ] && {
        break
      }

      # shellcheck disable=SC2059
      char="$(printf "\\$(printf '%03o' "$hex")")"

      # NOTE: if $char is empty, it because `dd` returned '\n' but `$(...)` 
      # removed it as trailing '\n', so I set $char as '\n' here
      [ -z "$char" ] && {
          LINE_N=$((LINE_N+1))
          char='
'
      }

      log trace "char: $WHITE$char"

      parse "${char:?}"

      CHAR_N=$((CHAR_N+1))
  done

  log debug 'finishing'

  # finish TEXT tag if file ends on it
  if [ "$STAGE" -eq 0 ]; then
    if [ "${open_tag_flag+x}" ]; then
      unset open_tag_flag
      printf '{' >> "$STAGE_BUFFER_1"
    fi
    
    buf=$(cat "$STAGE_BUFFER_1")
    # Only add text element if buffer is not empty
    if [ -n "$buf" ]; then
      yq -o j -i "$AST_key += [{
        \"type\": \"text\",
        \"value\": \"$(json_escape "$buf")\"
      }]" "$AST"
    fi
  fi

  # return the output
  # shellcheck disable=SC2086
  yq ${OUTPUT_ARGS:-} -o j "$AST"
fi