#!/bin/sh
# Usage: make.sh [build|check[test1 test2 ...]] [--norun] [--debug] [--color]
# Options:
#   build         Build the library and app (default if no mode is provided).
#   watch         Build the library and app and watch for changes.
#   check         Build tests; runs them unless --norun is specified.
#   --norun       (check only) Build tests but do not run them.
#   --debug       Build with -O0 (debug mode).
#   --color       Pass -fdiagnostics-color=always to compiler.
#   help, --help  Show this help message.
#   test1 test2   (check only) Run specific tests by name (without .c extension)

check_dependencies() {
  for dep in cc ar; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      echo "Error: Required dependency '$dep' not found." >&2
      exit 1
    fi
  done
  
  # Check for either fswatch or inotifywait
  if ! command -v fswatch >/dev/null 2>&1 && ! command -v inotifywait >/dev/null 2>&1; then
    echo "Error: Neither fswatch nor inotifywait found. Please install one of them." >&2
    echo "  On macOS: brew install fswatch" >&2
    echo "  On Linux: sudo apt install inotify-tools" >&2
    exit 1
  fi
}
check_dependencies

print_help() {
  cat <<EOF
Usage: $0 [build|check[test1 test2 ...]] [--norun] [--debug] [--color]
  build         Build the library and app (default).
  watch         Build the library and app and watch for changes.
  check         Build tests; runs them unless --norun is specified.
  --norun       (check only) Build tests but do not run them.
  --debug       Build with debug flags (-O0).
  --color       Force colored compiler diagnostics.
  test1 test2   (check only) Run specific tests by name (without .c extension)
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
CFLAGS="-Wall -Wextra -Werror -pedantic -fsanitize=address -fanalyzer"
STD_FLAGS="-std=c99"
COLOR_FLAG=""
DEBUG=0

# Process options
while [ $# -gt 0 ]; do
  case "$1" in
    --norun)
      RUN_TESTS=0
      ;;
    --debug)
      if ! command -v gdb >/dev/null 2>&1; then
        echo "Error: Required dependency '$dep' not found." >&2
        exit 1
      fi
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

case "$MODE" in
  watch)
    find . -type d | nix run .#watch -- 'sh ./make.sh build && sh ./make.sh check' -p '*.c' -p '*.h' 2>&1
    ;;
  build)
    mkdir -p target
    echo "# Build library"
    # shellcheck disable=SC2086
    cc $CFLAGS $OPTFLAGS $STD_FLAGS -c hectic.c -o target/hectic.o
    ar rcs target/libhectic.a target/hectic.o
    ;;
  check)
    mkdir -p target/test
    
    # Get list of tests to run
    TESTS_TO_RUN=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --norun|--debug|--color)
          shift
          ;;
        *)
          TESTS_TO_RUN+=("$1")
          shift
          ;;
      esac
    done

    # Check if any requested test doesn't exist
    for test in "${TESTS_TO_RUN[@]}"; do
        if [ ! -f "test/${test}.c" ]; then
            echo "Error: Test '${test}' not found in test directory"
            exit 1
        fi
    done

    echo "TESTS_TO_RUN: ${TESTS_TO_RUN[@]}"
    for test_file in test/*.c; do
      test_name=$(basename "${test_file%.c}")
      
      # Skip if specific tests are requested and this isn't one of them
      if [ ${#TESTS_TO_RUN[@]} -ne 0 ] && ! [[ " ${TESTS_TO_RUN[*]} " =~ " ${test_name} " ]]; then
        continue
      fi

      exe="target/test/$test_name"
      echo "Building test: $test_name"
      # shellcheck disable=SC2086
      cc $CFLAGS $OPTFLAGS -I. "$test_file" -Ltarget -lhectic $LDFLAGS -o "$exe"
      if [ "$?" -ne 0 ]; then
        exit 1
      fi
      if [ "$RUN_TESTS" -eq 1 ]; then
        if [ "$DEBUG" -eq 1 ]; then
          env LOG_LEVEL="$LOG_LEVEL" gdb -tui "$exe"
        fi
        env LOG_LEVEL="$LOG_LEVEL" "$exe"

        if [ $? -ne 0 ]; then
          exit 1
        fi
      fi
    done
    ;;
  *)
    print_help
    exit 1
    ;;
esac
