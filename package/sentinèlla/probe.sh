#!/usr/bin/env dash
set -euo pipefail
socat -V >/dev/null
dash -c 'echo ok' >/dev/null

socat -T5 -t5 TCP-LISTEN:"${PORT:-5988}",reuseaddr,fork EXEC:"dash ${LOOP_FILE:-probe-loop}"
