#!/bin/dash

# Hectic shell logger
#
# Usage:
#   # Including
#   . <this file>
#
#   # Required 
#   colors.sh
#
#   # In your script (recommended: do NOT export HECTIC_NAMESPACE)
#   HECTIC_NAMESPACE="my-script"   # optional, defaults to basename "$0"
#   #   # Then use:
#   log info   'starting up'
#   log debug  "value=${val}"
#   log error  "failed: ${WHITE}${reason}${NC} red text again"
#
#   # Note:
#   When you use NC to reset terminal colors inside log output,
#   it resets back to the log level’s color instead of the terminal default.

: "${HECTIC_NAMESPACE="$(basename "$0")"}"
: "${HECTIC_LOG:=trace}"  # e.g. "info;ns1=debug;ns2=trace"

validate_log_level_spec() {
    spec=$HECTIC_LOG

    levels="trace debug info notice warn error"

    ok_level() {
        for l in $levels; do
            [ "$l" = "$1" ] && return 0
        done
        return 1
    }

    oldIFS=$IFS
    IFS=';'
    # shellcheck disable=SC2086
    set -- $spec
    IFS=$oldIFS

    for tok; do
        case $tok in
            *=*)
                ns=${tok%%=*}
                lvl=${tok#*=}
                [ -n "$ns" ] || return 1
                ok_level "$lvl" || return 1
                ;;
            *)
                ok_level "$tok" || return 1
                ;;
        esac
    done

    return 0
}

validate_log_level_spec || { printf "%b%b\n" "${BBLACK}${HECTIC_NAMESPACE}> " "${color}invalid HECTIC_LOG syntax${NC}" "$@" >&2; exit 1; }

log_level_num() {
    case $1 in
        trace)  printf %s 0 ;;
        debug)  printf %s 1 ;;
        info)   printf %s 2 ;;
        notice) printf %s 3 ;;
        warn)   printf %s 4 ;;
        error)  printf %s 5 ;;
        *)      printf %s 2 ;; # default info
    esac
}


log_effective_level() {
    spec=$HECTIC_LOG
    ns=$HECTIC_NAMESPACE

    default_level=
    ns_level=

    oldIFS=$IFS
    IFS=';'
    # shellcheck disable=SC2086
    set -- $spec
    IFS=$oldIFS

    for tok; do
        case $tok in
            *=*)
                name=${tok%%=*}
                lvl=${tok#*=}
                [ "$name" = "$ns" ] && ns_level=$lvl
                ;;
            *)
                [ -z "$default_level" ] && default_level=$tok
                ;;
        esac
    done

    printf '%s\n' "${ns_level:-${default_level:-info}}"
}

log_allowed() {
    msg_level="${1:?}"
    eff_level="$(log_effective_level)"

    msg_n="$(log_level_num "$msg_level")"
    eff_n="$(log_level_num "$eff_level")"

    [ "$msg_n" -ge "$eff_n" ]
}

# log(level, text...)
log() {
    delimetr=${DELIMETR:-' '};
    level="${1:?}"; shift
    log_allowed "$level" || return 0

    case "$level" in
        trace)   color="$MAGENTA"  ;;
        debug)   color="$BLUE"     ;;
        info)    color="$GREEN"    ;;
        notice)  color="$CYAN"     ;;
        warn)    color="$YELLOW"   ;;
        error)   color="$RED"      ;;
        *)       color="$WHITE"    ;;
    esac



    # shellcheck disable=SC1003
    fmt="$(printf "%s$delimetr" "$@" | sed 's/\\033\[0m/''\'"$color"'/g')"
    shift
    printf "%b%b\n" "${BBLACK}${HECTIC_NAMESPACE}> " "$color$fmt$NC" >&2
}
