#!/bin/sh
# Usage: make.sh [build|check] [--norun] [--debug] [--color]
# Options:
#   build         Build the library and app (default if no mode is provided).
#   watch         Build the library and app and watch for changes.
#   run           Build and run the app.
#   check         Build tests; runs them unless --norun is specified.
#   --norun       (check only) Build tests but do not run them.
#   --debug       Build with -O0 (debug mode).
#   --color       Pass -fdiagnostics-color=always to compiler.
#   help, --help  Show this help message.

check_dependencies() {
  for dep in cc ar pager; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      echo "Error: Required dependency '$dep' not found." >&2
      exit 1
    fi
  done
}
check_dependencies

print_help() {
  cat <<EOF
Usage: $0 [build|check] [--norun] [--debug] [--color]
  build         Build the library and app (default).
  watch         Build the library and app and watch for changes.
  run           Build and run the app.
  check         Build tests; runs them unless --norun is specified.
  --norun       (check only) Build tests but do not run them.
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
RUN_TESTS=1
OPTFLAGS="-O2"
CFLAGS="-Wall -Wextra -Werror -pedantic -fsanitize=address"
LDFLAGS="-lhectic"
STD_FLAGS="-std=c99"
COLOR_FLAG=""

MODE="${1:-build}"
shift

# Process options
while [ $# -gt 0 ]; do
  case "$1" in
    --norun)
      RUN_TESTS=0
      ;;
    --debug)
      OPTFLAGS="-O0"
      ;;
    --color)
      COLOR_FLAG="-fdiagnostics-color=always"
      ;;
    *)
      echo "Unknown option: $1"
      print_help
      exit 1
      ;;
  esac
  shift
done

if [ -n "$COLOR_FLAG" ]; then
  CFLAGS="$CFLAGS $COLOR_FLAG"
fi

build() {
  mkdir -p target
  echo "# Build app"
  # shellcheck disable=SC2086
  cc $CFLAGS $OPTFLAGS main.c $LDFLAGS -lhectic -o target/prettify
}

case "$MODE" in
  watch)
    find . -type d | nix run .#watch -- 'sh ./make.sh build && sh ./make.sh check' -i -p '*.c' -p '*.h' 2>&1
    ;;
  build)
    build
    ;;
  run)
    build && ./target/prettify
    ;;
  check)
    echo "No tests to run"
    ;;
  *)
    print_help
    exit 1
    ;;
esac
