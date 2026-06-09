load_sops_shell_quote() {
  printf "'"
  printf '%s' "$1" | sed "s/'/'\"'\"'/g"
  printf "'"
}

load_sops_normalize_key() {
  load_sops_normalized_key=$(printf '%s' "$1" | tr '.-' '__' | tr '[:lower:]' '[:upper:]')

  case "$load_sops_normalized_key" in
    ''|[!A-Z_]*|*[!A-Z0-9_]*)
      printf 'load-sops: invalid environment name after key normalization\n' >&2
      return 1
      ;;
  esac

  printf '%s\n' "$load_sops_normalized_key"
}

load_sops_env_from_sops_file() {
  load_sops_file=$1
  load_sops_extract=${2-}

  if ! command -v sops >/dev/null 2>&1; then
    printf 'load-sops: required tool `sops` not found\n' >&2
    return 1
  fi

  if ! command -v yq >/dev/null 2>&1; then
    printf 'load-sops: required tool `yq` not found\n' >&2
    return 1
  fi

  load_sops_decrypted=''
  load_sops_attempt=0
  load_sops_max_retries=${LOAD_SOPS_MAX_RETRIES:-1}
  load_sops_prompt=${LOAD_SOPS_PROMPT:-0}

  while :; do
    if [ -n "$load_sops_extract" ]; then
      if load_sops_decrypted=$(sops -d --extract "$load_sops_extract" "$load_sops_file" 2>/dev/null); then
        load_sops_status=0
      else
        load_sops_status=$?
      fi
    else
      if load_sops_decrypted=$(sops -d "$load_sops_file" 2>/dev/null); then
        load_sops_status=0
      else
        load_sops_status=$?
      fi
    fi

    if [ "$load_sops_status" -eq 0 ]; then
      break
    fi

    if [ "$load_sops_prompt" != 1 ]; then
      printf 'load-sops: failed to decrypt file\n' >&2
      return 1
    fi

    if ! [ -t 0 ] || ! [ -r /dev/tty ]; then
      printf 'load-sops: decrypt failed and prompt requested, but no TTY is available\n' >&2
      return 1
    fi

    load_sops_attempt=$((load_sops_attempt + 1))
    if [ "$load_sops_max_retries" != 0 ] && [ "$load_sops_attempt" -gt "$load_sops_max_retries" ]; then
      printf 'load-sops: decrypt failed after configured retries\n' >&2
      return 1
    fi

    load_sops_use_script=${LOAD_SOPS_USE_SCRIPT:-auto}
    load_sops_quoted_file=$(load_sops_shell_quote "$load_sops_file") || return 1
    load_sops_quoted_tty=$(load_sops_shell_quote "$(tty)") || return 1
    case "$load_sops_use_script" in
      auto)
        if command -v script >/dev/null 2>&1 && [ -t 0 ]; then
          if script -qefc "env GPG_TTY=$load_sops_quoted_tty sops --output /dev/null -d $load_sops_quoted_file" /dev/null >/dev/null 2>&1; then
            load_sops_script_status=0
          else
            load_sops_script_status=$?
          fi
          if [ "$load_sops_script_status" -eq 0 ]; then
            continue
          fi
        fi
        ;;
      1)
        if ! command -v script >/dev/null 2>&1; then
          printf 'load-sops: required tool `script` not found\n' >&2
          return 1
        fi
        if script -qefc "env GPG_TTY=$load_sops_quoted_tty sops --output /dev/null -d $load_sops_quoted_file" /dev/null >/dev/null 2>&1; then
          load_sops_script_status=0
        else
          load_sops_script_status=$?
        fi
        if [ "$load_sops_script_status" -eq 0 ]; then
          continue
        fi
        ;;
      0)
        ;;
      *)
        printf 'load-sops: LOAD_SOPS_USE_SCRIPT must be auto, 0, or 1\n' >&2
        return 1
        ;;
    esac

    printf 'load-sops: enter SOPS_AGE_KEY_CMD: ' >/dev/tty
    if ! IFS= read -r SOPS_AGE_KEY_CMD </dev/tty; then
      printf 'load-sops: failed to read prompt input\n' >&2
      return 1
    fi
    export SOPS_AGE_KEY_CMD
  done

  load_sops_env_from_yaml_text "$load_sops_decrypted"
}

load_sops_env_from_yaml_file() {
  load_sops_file=$1

  if ! command -v yq >/dev/null 2>&1; then
    printf 'load-sops: required tool `yq` not found\n' >&2
    return 1
  fi

  load_sops_env_from_yaml_text "$(cat "$load_sops_file")"
}

load_sops_env_from_yaml_text() {
  load_sops_yaml=$1
  load_sops_seen=''

  if load_sops_keys=$(printf '%s' "$load_sops_yaml" | yq -r 'keys | .[]' 2>/dev/null); then
    load_sops_keys_status=0
  else
    load_sops_keys_status=$?
  fi

  if [ "$load_sops_keys_status" -ne 0 ]; then
    printf 'load-sops: failed to inspect YAML top-level keys\n' >&2
    return 1
  fi

  while IFS= read -r load_sops_key; do
    [ -n "$load_sops_key" ] || continue

    load_sops_name=$(load_sops_normalize_key "$load_sops_key") || return 1

    case "
$load_sops_seen
" in
      *"
$load_sops_name
"*)
        if [ "${LOAD_SOPS_ALLOW_COLLISIONS:-0}" != 1 ]; then
          printf 'load-sops: normalized environment name collision\n' >&2
          return 1
        fi
        ;;
    esac
    load_sops_seen=${load_sops_seen}${load_sops_seen:+"
"}$load_sops_name

    load_sops_kind=$(printf '%s' "$load_sops_yaml" | yq -r '."'"$load_sops_key"'" | kind' 2>/dev/null) || {
      printf 'load-sops: failed to inspect YAML value kind\n' >&2
      return 1
    }
    load_sops_tag=$(printf '%s' "$load_sops_yaml" | yq -r '."'"$load_sops_key"'" | tag' 2>/dev/null) || {
      printf 'load-sops: failed to inspect YAML value tag\n' >&2
      return 1
    }

    if [ "$load_sops_kind" != scalar ]; then
      printf 'load-sops: top-level YAML values must be scalars\n' >&2
      return 1
    fi

    if [ "$load_sops_tag" = '!!null' ]; then
      printf 'load-sops: top-level YAML null values are not supported\n' >&2
      return 1
    fi

    if [ "${LOAD_SOPS_OVERWRITE:-1}" = 0 ]; then
      eval 'load_sops_already_set=${'"$load_sops_name"'+x}'
      if [ -n "$load_sops_already_set" ]; then
        continue
      fi
    fi

    load_sops_value=$(printf '%s' "$load_sops_yaml" | yq -r '."'"$load_sops_key"'"' 2>/dev/null) || {
      printf 'load-sops: failed to read YAML scalar value\n' >&2
      return 1
    }
    load_sops_quoted=$(load_sops_shell_quote "$load_sops_value") || return 1
    eval "export $load_sops_name=$load_sops_quoted"
  done <<EOF
$load_sops_keys
EOF
}
