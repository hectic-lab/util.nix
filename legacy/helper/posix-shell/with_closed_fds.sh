#!/bin/dash

# with_closed_fds -- run command with leaked file descriptors closed
#
# Shell libraries (e.g. hectic logger) may open extra file descriptors
# (like fd 3 as a dup of stderr). Child processes inherit these fds.
# Long-running daemons (postgres, postgrest) that keep fd 3 open can
# prevent the terminal from returning to the prompt even after the
# spawning script exits.
#
# Usage:
#   with_closed_fds pg_ctl -D "$data" -w start
#   with_closed_fds postgrest "$config" > "$log" 2>&1 &
#
# Runs the command in a subshell where fds 3-9 are redirected to
# /dev/null. The parent shell's fd table is untouched.
with_closed_fds() {
    (
        exec 3>/dev/null 4>/dev/null 5>/dev/null 6>/dev/null 7>/dev/null 8>/dev/null 9>/dev/null
        "$@"
    )
}
