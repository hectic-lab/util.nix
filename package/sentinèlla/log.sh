#!/bin/dash

log() {
    level="$1"; shift
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
    fmt="$(printf "%s" "$1" | sed 's/\\033\[0m/''\'"$color"'/g')"
    shift
    printf "%b\n" "$color$fmt$NC" "$@"
}
