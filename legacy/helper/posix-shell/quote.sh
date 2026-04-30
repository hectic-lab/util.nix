quote() { printf "'%s'" "$(printf %s "$1" | sed "s/'/'\\\\''/g")"; }
