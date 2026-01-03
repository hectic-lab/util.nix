# hecticPatchInclude(including_path.., target_path)
hecticPatchInclude() {
    [ $# -ge 2 ] || return 2

    target_path=$1
    for a in "$@"; do target_path=$a; done  # last arg

    tmp="${target_path}.tmp.$$"

    awk '
        BEGIN { buf=""; n=ARGC-1 }               # last arg is target
        (ARGIND < n) { buf = buf $0 ORS; next }  # includes

        FNR==1 {
            if ($0 ~ /^#!/) { print; printf "%s", buf; next }
            else            { printf "%s", buf }
        }
        { print }
    ' "$@" >"$tmp" && mv "$tmp" "$target_path"
}
