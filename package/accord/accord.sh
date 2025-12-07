#!/bin/dash

exec 2>err.log

PANEL_H=20

old_stty=$(stty -g)

main() {
  make_panel_space
  
  cols=$(tput cols)
  lines=$(tput lines)
  top=$(( lines - PANEL_H + 1 ))
  [ "$top" -lt 1 ] && top=1
  
  msg="Welcome to accord"
  w=$(( ${#msg} + 4 ))
  h=5
  x=$(( (cols - w) / 2 ))
  y=$(( top + (PANEL_H - h) / 2 ))
  
  draw_box "$x" "$y" "$w" "$h" "$msg"
  
  key=$(read_key)
  
  case "$key" in
    l)
      clear_panel
      msg="I love you"
      w=$(( ${#msg} + 4 ))
      x=$(( (cols - w) / 2 ))
      draw_box "$x" "$y" "$w" "$h" "$msg"
      key=$(read_key)
      ;;
    s)
      clear_panel

      key=$(read_key)
  esac
}

clear_panel() {
    cols=$(tput cols)
    lines=$(tput lines)
    top=$(( lines - PANEL_H + 1 ))
    [ "$top" -lt 1 ] && top=1

    row=$top
    while [ "$row" -le "$lines" ]; do
        printf '\033[%d;1H\033[2K' "$row"
        row=$((row+1))
    done
}

cleanup() {
    clear_panel

    stty "$old_stty"
    tput sgr0
    tput cnorm

    # NOTE(yukkop): move cursor to where panel started, so shell prompt
    # continues “right after” previous output
    lines=$(tput lines)
    row=$(( lines - PANEL_H + 1 ))
    [ "$row" -lt 1 ] && row=1
    printf '\033[%d;1H' "$row"
}
trap cleanup EXIT INT TERM

stty -echo raw
tput civis

draw_box() {
    x=$1
    y=$2
    w=$3
    h=$4
    text=$5

    row=0
    while [ "$row" -lt "$h" ]; do
        printf '\033[%d;%dH' "$((y+row))" "$x"

        case "$row" in
            0|$((h-1)))
                printf '+'
                printf '%*s' "$((w-2))" '' | tr ' ' '-'
                printf '+'
                ;;
            *)
                if [ "$row" -eq 2 ] && [ -n "$text" ]; then
                    printf '| %s' "$text"
                    pad=$(( w - 3 - ${#text} ))
                    [ "$pad" -gt 0 ] && printf '%*s' "$pad" ' '
                    printf '|'
                else
                    printf '|'
                    printf '%*s' "$((w-2))" ' '
                    printf '|'
                fi
                ;;
        esac

        row=$((row+1))
    done
}

make_panel_space() {
    i=0
    while [ "$i" -lt "$PANEL_H" ]; do
        printf '\n'
        i=$((i+1))
    done
}

read_key() {
    k=$(dd bs=1 count=1 2>/dev/null || true)
    if [ "$k" = "$(printf '\033')" ]; then
        k="$k$(dd bs=1 count=2 2>/dev/null || true)"
    fi
    printf '%s' "$k"
}

. ./frames.sh

if ! [ ${AS_LIBRARY+x} ]; then
  main
fi
