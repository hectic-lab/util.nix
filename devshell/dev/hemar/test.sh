#!/bin/dash

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

if [ "${1:?}" = 'test' ]; then
  dash "${ROOT_DIR}/package/hemar/test.sh"
fi
