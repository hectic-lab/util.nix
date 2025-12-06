#!/bin/dash

# LISTEN
# ssh -NL localhost:42001:localhost:42001 root@hecticb
#
# socat TCP-LISTEN:42001,bind=127.0.0.1,fork - | mpv --no-cache --demuxer=rawaudio --audio-channels=mono --audio-samplerate=44100 --aid=1 -


# SEND
# ssh -NR localhost:42002:localhost:42002 root@hectic-lab
#
# ffmpeg -f pulse -i default -t 10 -ar 44100 -f wav tcp:127.0.0.1:42002

old_stty=$(stty -g)

cleanup() {
    stty "$old_stty"
    tput rmcup 2>/dev/null || printf '\033[?1049l'  # leave alt screen
    tput sgr0
    tput cnorm
}
trap cleanup EXIT INT TERM

# enter alternate screen
tput smcup 2>/dev/null || printf '\033[?1049h'
stty -echo raw
tput civis

msg="Press any key to continue"
cols=$(tput cols)
lines=$(tput lines)

w=$(( ${#msg} + 4 ))
h=5
x=$(( (cols - w) / 2 ))
y=$(( (lines - h) / 2 ))

clear_screan() {
  # clear *inside* alt screen
  printf '\033[2J'
  printf '\033[H'
}

clear_screan

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

msg="Welcome to accord"

cols=$(tput cols)
lines=$(tput lines)

w=$(( ${#msg} + 4 ))
h=5
x=$(( (cols - w) / 2 ))
y=$(( (lines - h) / 2 ))

# first page
draw_box "$x" "$y" "$w" "$h" "$msg"

read_key() {
    k=$(dd bs=1 count=1 2>/dev/null || true)
    if [ "$k" = "$(printf '\033')" ]; then
        k="$k$(dd bs=1 count=2 2>/dev/null || true)"
    fi
    printf '%s' "$k"
}

key=$(read_key)

case "$key" in
  l) 
    clear_screan

    msg="I love you"
    w=$(( ${#msg} + 4 ))
    x=$(( (cols - w) / 2 ))

    draw_box "$x" "$y" "$w" "$h" "$msg"
    key=$(read_key)
  ;;
esac
