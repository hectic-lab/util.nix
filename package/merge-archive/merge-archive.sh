# shellcheck shell=dash
# shellcheck disable=SC3043

: "${SCRIPT_NAME:=$(basename "$0")}"
SCRIPT_NAME=${SCRIPT_NAME%%.sh}

pager_or_cat_init

help() {
  # shellcheck disable=SC2059
  printf "$(cat <<EOF
${BRED}TLDR; For the most lazy${NC}
${BCYAN}$SCRIPT_NAME archive.tar.gz${NC}    ${BRED}Merge${NC} archive into the current git repo

${BGREEN}Usage:${NC} $SCRIPT_NAME [OPTIONS] <ARCHIVE> [TARGET_DIR]

Merge an archive into a git repository using ${CYAN}--allow-unrelated-histories${NC}.

${BGREEN}Arguments:${NC}
  ${BCYAN}ARCHIVE${NC}              Archive file to import
  ${BCYAN}TARGET_DIR${NC}           Target directory inside a git work tree (default: ${BBLACK}$PWD${NC})

${BGREEN}Options:${NC}
  ${BCYAN}--no-strip${NC}           Keep the archive root directory intact
  ${BCYAN}--strip${NC}              Force stripping a single top-level directory
  ${BCYAN}-m${NC}, ${BCYAN}--message${NC} ${CYAN}MSG${NC}   Merge commit message
  ${BCYAN}-h${NC}, ${BCYAN}--help${NC}            Show this help message

${BGREEN}Formats:${NC}
  ${BBLACK}.tar${NC} ${BBLACK}.tar.gz${NC} ${BBLACK}.tgz${NC} ${BBLACK}.tar.bz2${NC} ${BBLACK}.tbz2${NC} ${BBLACK}.tar.xz${NC} ${BBLACK}.txz${NC} ${BBLACK}.zip${NC}
  File-magic fallback is used when the extension is missing or ambiguous.

${BGREEN}Examples:${NC}
  $SCRIPT_NAME release.tar.gz
  $SCRIPT_NAME release.zip /path/to/repo
  $SCRIPT_NAME --no-strip archive.tar.gz
  $SCRIPT_NAME --message "Import upstream v2.0" release.tar.gz

EOF
)" | "$PAGER_OR_CAT"
}

detect_archive_format() {
  local archive="$1"

  case "$archive" in
    *.tar.gz|*.tgz)
      printf '%s\n' 'tar.gz'
      return 0
      ;;
    *.tar.bz2|*.tbz2)
      printf '%s\n' 'tar.bz2'
      return 0
      ;;
    *.tar.xz|*.txz)
      printf '%s\n' 'tar.xz'
      return 0
      ;;
    *.tar)
      printf '%s\n' 'tar'
      return 0
      ;;
    *.zip)
      printf '%s\n' 'zip'
      return 0
      ;;
  esac

  case "$(file -b --mime-type "$archive")" in
    application/zip)
      printf '%s\n' 'zip'
      ;;
    application/x-tar)
      printf '%s\n' 'tar'
      ;;
    application/gzip)
      printf '%s\n' 'tar.gz'
      ;;
    application/x-bzip2)
      printf '%s\n' 'tar.bz2'
      ;;
    application/x-xz)
      printf '%s\n' 'tar.xz'
      ;;
    *)
      log error "unsupported archive format: $archive"
      log info "supported formats: .tar .tar.gz .tgz .tar.bz2 .tbz2 .tar.xz .txz .zip"
      exit 9
      ;;
  esac
}

extract_archive() {
  local archive="$1"
  local dest="$2"
  local format="$3"

  case "$format" in
    tar)
      tar -xf "$archive" -C "$dest"
      ;;
    tar.gz)
      tar -xzf "$archive" -C "$dest"
      ;;
    tar.bz2)
      tar -xjf "$archive" -C "$dest"
      ;;
    tar.xz)
      tar -xJf "$archive" -C "$dest"
      ;;
    zip)
      unzip -q "$archive" -d "$dest"
      ;;
    *)
      log error "unsupported archive format: $archive"
      exit 9
      ;;
  esac
}

single_top_level_dir() {
  local dir="$1"
  local entry_count=0
  local top_level_dir=""
  local entry

  for entry in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
    [ -e "$entry" ] || continue
    entry_count=$((entry_count + 1))
    if [ "$entry_count" -gt 1 ]; then
      return 1
    fi
    if [ -d "$entry" ]; then
      top_level_dir="$entry"
    else
      return 1
    fi
  done

  if [ "$entry_count" -eq 1 ] && [ -n "$top_level_dir" ]; then
    printf '%s\n' "$top_level_dir"
    return 0
  fi

  return 1
}

cleanup() {
  if [ -n "${TARGET_REPO_ROOT:-}" ] && [ -n "${TEMP_REF:-}" ]; then
    git -C "$TARGET_REPO_ROOT" update-ref -d "$TEMP_REF" >/dev/null 2>&1 || :
  fi

  if [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR" ]; then
    rm -rf "$WORK_DIR"
  fi
}

ARCHIVE=""
TARGET_DIR="$PWD"
AUTO_STRIP=1
MERGE_MESSAGE=""

if [ $# -eq 0 ]; then
  log error "archive argument is required"
  help
  exit 3
fi

while [ $# -gt 0 ]; do
  case $1 in
    -h|--help)
      help
      exit 0
      ;;
    --no-strip)
      AUTO_STRIP=0
      shift
      ;;
    --strip)
      AUTO_STRIP=1
      shift
      ;;
    -m|--message)
      if [ $# -lt 2 ]; then
        log error "--message requires an argument"
        exit 3
      fi
      MERGE_MESSAGE="$2"
      shift 2
      ;;
    --*|-*)
      log error "unknown option: $1"
      exit 9
      ;;
    *)
      if [ -z "$ARCHIVE" ]; then
        ARCHIVE="$1"
      elif [ "$TARGET_DIR" = "$PWD" ]; then
        TARGET_DIR="$1"
      else
        log error "unexpected argument: $1"
        exit 9
      fi
      shift
      ;;
  esac
done

if [ -z "$ARCHIVE" ]; then
  log error "no archive specified"
  help
  exit 3
fi

if [ ! -e "$ARCHIVE" ]; then
  log error "archive not found: $ARCHIVE"
  exit 1
fi

if [ ! -d "$TARGET_DIR" ]; then
  log error "target directory not found: $TARGET_DIR"
  exit 1
fi

if ! TARGET_REPO_ROOT=$(git -C "$TARGET_DIR" rev-parse --show-toplevel 2>/dev/null); then
  log error "target directory is not inside a git repository: $TARGET_DIR"
  exit 1
fi

if ! git -C "$TARGET_REPO_ROOT" rev-parse --verify HEAD >/dev/null 2>&1; then
  log error "target repository has no commits yet"
  exit 1
fi

if [ -n "$(git -C "$TARGET_REPO_ROOT" status --porcelain --untracked-files=all)" ]; then
  log error "target repository has uncommitted changes"
  log warn "commit, stash, or clean the tree before merging"
  exit 1
fi

trap cleanup EXIT INT HUP TERM

ARCHIVE_BASENAME=${ARCHIVE##*/}
: "${MERGE_MESSAGE:=Merge archive ${ARCHIVE_BASENAME}}"

log notice "merging ${BCYAN}${ARCHIVE_BASENAME}${NC} into ${BCYAN}${TARGET_REPO_ROOT}${NC}"

WORK_DIR=$(mktemp -d)
EXTRACT_DIR="$WORK_DIR/extracted"
TEMP_REPO="$WORK_DIR/repo"
mkdir -p "$EXTRACT_DIR" "$TEMP_REPO"

log info "unpacking archive"
ARCHIVE_FORMAT=$(detect_archive_format "$ARCHIVE")
extract_archive "$ARCHIVE" "$EXTRACT_DIR" "$ARCHIVE_FORMAT"

SOURCE_DIR="$EXTRACT_DIR"
if [ "$AUTO_STRIP" -eq 1 ]; then
  if STRIPPED_DIR=$(single_top_level_dir "$EXTRACT_DIR"); then
    SOURCE_DIR=$STRIPPED_DIR
  fi
fi

log info "initializing temporary git repository"
git -C "$TEMP_REPO" init -q
git -C "$TEMP_REPO" config user.email "merge-archive@local"
git -C "$TEMP_REPO" config user.name "merge-archive"

cp -R "$SOURCE_DIR"/. "$TEMP_REPO"/

git -C "$TEMP_REPO" add -A
git -C "$TEMP_REPO" commit -q -m "archive: $ARCHIVE_BASENAME"

log info "fetching temporary repository"
TEMP_REF="refs/merge-archive/import/$$"
git -C "$TARGET_REPO_ROOT" fetch -q "$TEMP_REPO" HEAD:"$TEMP_REF"

log notice "merging with --allow-unrelated-histories"
if ! git -C "$TARGET_REPO_ROOT" merge \
  --allow-unrelated-histories \
  -m "$MERGE_MESSAGE" \
  "$TEMP_REF"; then
  log error "merge conflict(s) detected"
  log warn "conflicted files:"
  git -C "$TARGET_REPO_ROOT" diff --name-only --diff-filter=U | while IFS= read -r conflicted_file; do
    [ -n "$conflicted_file" ] || continue
    log warn "  $conflicted_file"
  done
  log warn "run 'git -C $TARGET_REPO_ROOT merge --abort' to cancel the merge"
  exit 1
fi

log notice "merge ${GREEN}complete${NC}"
