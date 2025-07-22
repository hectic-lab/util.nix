printf '\033[0;34mDetecting local directories...\033[0m\n'
if git_root=$($BIN_GIT rev-parse --show-toplevel 2>/dev/null); then
  LOCAL_DIR="$git_root"
  printf '\033[0;32mFound git root: \033[1;37m%s\033[0m\n' "$LOCAL_DIR"
else
  LOCAL_DIR="$(pwd)"
  printf '\033[1;33mNot in git repo, using current dir: \033[1;37m%s\033[0m\n' "$LOCAL_DIR"
  printf 'Are you realy want continue? (y/n):\n'
  read -r CONTINUE
  if [ "$CONTINUE" != "y" ]; then
    printf '\033[0;31mAborting...\033[0m\n'
    exit 0
  fi
fi
