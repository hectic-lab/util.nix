#socat TCP-LISTEN:42002,bind=127.0.0.1,fork - | mpv --no-cache --demuxer=rawaudio --audio-channels=mono --audio-samplerate=44100 --aid=1 -
#ffmpeg -f pulse -i default -t 10 -ar 44100 -f wav tcp:127.0.0.1:42002

TUDA=42002
SUDA=42001
MIDLEHOST='root@hectic-lab'

req() {
  command=$1
  if ! command -v "$1" >/dev/null; then
      log error "Required tool ("$1") are not installed."
      exit 127
  fi
}

req ffmpeg
req socat
req mpv

main() {
  case $1 in
    listen|talk|test)
      [ "${SUBCOMMAND+x}" ] && { 
        log error "ambiguous subcommand, decide ${WHITE}$SUBCOMMAND ${NC}or ${WHITE}$1";
        exit 2;
      }
      SUBCOMMAND=$1
      shift
    ;;
    --*|-*)
      log error "argument $WHITE$1$NC does not exists"
      exit 9
    ;;
    *)
      log error "subcommand $WHITE$1$NC does not exists"
      exit 9
    ;;
  esac

  "$SUBCOMMAND"
}

# test listen -> talk localy via tcp sock
test() {
  :
}

listen() {
  #ssh -NL "localhost:${SUDA}:localhost:${SUDA}" "$MIDLEHOST"
  socat TCP-LISTEN:${SUDA},bind=127.0.0.1,fork - | mpv --no-cache --demuxer=rawaudio --audio-channels=mono --audio-samplerate=44100 --aid=1 -
}

talk() {
  #ssh -NR "localhost:${TUDA}:localhost:${TUDA}" "$MIDLEHOST"
  ffmpeg -f pulse -i default -t 10 -ar 44100 -f wav tcp:127.0.0.1:${TUDA}
}

main "$@"
