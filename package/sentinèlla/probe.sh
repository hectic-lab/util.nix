#!/bin/dash

socat -T5 -t5 TCP-LISTEN:"${PORT:-5988}",reuseaddr,fork EXEC:"dash $LOOP_FILE"
