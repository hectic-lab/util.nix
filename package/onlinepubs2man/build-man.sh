# Batch-convert many HTML files to man(7) pages and install locally (~/.local/share/man)

# nix shell nixpkgs#pandoc nixpkgs#man-db nixpkgs#gzip -c sh -eu <<'SH'

sect=7
dest="$HOME/.local/share/man/man$sect"
build="$(mktemp -d)"
mkdir -p "$dest" "$build"

# post-process pandoc's roff so mandb can parse NAME
# 
fix_name_section() {
  awk 'BEGIN { inside=0 }
  $0 ~ /^\.(SS|SH) NAME$/ { $0 = ".SH NAME"; inside=1 }
  inside && /\\\[em]/ { gsub(/\\\[em]/,"\\-") }
  inside && /^\.RE$/ { inside=0 }
  { print }' "$1"
}

# find all *.html|*.htm under current dir (recursive)
find . -type f \( -iname '*.html' -o -iname '*.htm' \) | while IFS= read -r f; do
  base="$(basename "${f%.*}")"
  # sanitize name: lowercase, spaces->-, strip weird chars
  name="$(printf '%s' "$base" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9.-' | tr -s '-')"
  out="$build/$name.$sect"

  # convert (pandoc will take <title> if present)
  pandoc -s "$f" -f html -t man \
    -M section="$sect" \
    -M date="$(date +'%B %Y')" \
    -o "$out.tmp"

  awk -f "$build/fix.awk" "$out.tmp" >"$out"
  rm -f "$out.tmp"

  gzip -9f "$out"
  install -m0644 "$out.gz" "$dest/"
done

# index once
mandb "$HOME/.local/share/man"
