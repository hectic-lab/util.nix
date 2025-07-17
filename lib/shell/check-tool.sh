check_tool() {
  if ! command -v "$1" >/dev/null; then
    echo "Required tool \`$2\` are not installed or binary \`$1\` not found." >&2
    exit 1
  fi
}
