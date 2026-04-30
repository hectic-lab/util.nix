#!/bin/sh
# Usage: make.sh [build|check] [--norun] [--debug] [--color]

PACKAGE_NAME="parse-uri"

check_dependencies() {
  for dep in cc; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      echo "Error: Required dependency '$dep' not found." >&2
      exit 1
    fi
  done
}
check_dependencies

# Default flags
OPTFLAGS="-O2"
CFLAGS="-Wall -Wextra -Werror -pedantic"
STD_FLAGS="-std=c99"

MODE="${1:-build}"
shift

build() {
  mkdir -p target
  echo "# Build $PACKAGE_NAME"
  # shellcheck disable=SC2086
  cc $CFLAGS $OPTFLAGS $STD_FLAGS main.c -o "target/$PACKAGE_NAME" $LDFLAGS $INCLUDES
}

case "$MODE" in
  build)
    build
    ;;
  check)
    echo "No tests to run"
    ;;
  *)
    exit 1
    ;;
esac
