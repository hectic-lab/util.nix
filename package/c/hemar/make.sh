#!/bin/sh
# Usage: make.sh [build|watch] [--debug] [--color]
# Options:
#   build         Build the postgres extension (default if no mode is provided).
#   watch         Build the extension and watch for changes.
#   --debug       Build with -O0 (debug mode).
#   --color       Pass -fdiagnostics-color=always to compiler.
#   help, --help  Show this help message.

check_dependencies() {
  for dep in gcc pg_config; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      echo "Error: Required dependency '$dep' not found." >&2
      exit 1
    fi
  done
  
  # Check for either fswatch or inotifywait for watch mode
  if [ "$MODE" = "watch" ] && ! command -v fswatch >/dev/null 2>&1 && ! command -v inotifywait >/dev/null 2>&1; then
    echo "Error: Neither fswatch nor inotifywait found. Please install one of them." >&2
    echo "  On macOS: brew install fswatch" >&2
    echo "  On Linux: sudo apt install inotify-tools" >&2
    exit 1
  fi
}

print_help() {
  cat <<EOF
Usage: $0 [build|watch] [--debug] [--color]
  build         Build the postgres extension (default).
  watch         Build the extension and watch for changes.
  --debug       Build with debug flags (-O0).
  --color       Force colored compiler diagnostics.
  help, --help  Display this help message.
EOF
}

# Show help if requested
case "$1" in
  help|--help)
    print_help
    exit 0
    ;;
esac

# Default flags
OPTFLAGS="-O2"
CFLAGS="-Wall -Wextra -pedantic -fPIC"
COLOR_FLAG=""
DEBUG=0

# Process options
while [ $# -gt 0 ]; do
  case "$1" in
    --debug)
      OPTFLAGS="-O0 -gdwarf-2 -g3 -Wno-error"
      DEBUG=1
      ;;
    --color)
      COLOR_FLAG="-fdiagnostics-color=always"
      ;;
    *)
      break
      ;;
  esac
  shift
done

MODE="${1:-build}"
shift 2> /dev/null

if [ -n "$COLOR_FLAG" ]; then
  CFLAGS="$CFLAGS $COLOR_FLAG"
fi

check_dependencies

# Get PostgreSQL include directory
PG_INCLUDE=$(pg_config --includedir-server)
PG_LIBDIR=$(pg_config --libdir)

case "$MODE" in
  watch)
    find . -type d | nix run .#watch -- 'sh ./make.sh build' -p '*.c' -p '*.h' 2>&1
    ;;
  build)
    mkdir -p target
    echo "# Building PostgreSQL extension"
    
    # Get hectic library paths from nix
    HECTIC_PATH=$(nix build --print-out-paths -f ../../../. c-hectic)
    HECTIC_INCLUDE="$HECTIC_PATH/include"
    HECTIC_LIB="$HECTIC_PATH/lib"
    
    # shellcheck disable=SC2086
    gcc $CFLAGS $OPTFLAGS -I$PG_INCLUDE -I$HECTIC_INCLUDE -shared -o target/hemar.so hemar.c -L$HECTIC_LIB -lhectic
    
    # Copy extension files to target directory
    cp hemar.control target/
    cp hemar--0.1.sql target/
    
    echo "Build complete. Files available in target/ directory."
    ;;
  *)
    print_help
    exit 1
    ;;
esac