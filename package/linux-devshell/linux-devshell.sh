NIX_HOOK="${HOME}/.nix-profile/etc/profile.d/nix.sh"

detect_shell() {
  self=detect_shell

  if [ "$0" != "$self" ]; then
    case "$0" in
      /*) [ -x "$0" ] && { printf '%s\n' "$0"; return 0; } ;;
      *)  command -v "$0" 2>/dev/null && return 0 ;;
    esac
  fi

  _shell="$(ps -p $$ -o args= 2>/dev/null | awk '{print $1}')"
  [ -n "$_shell" ] && command -v "$_shell" 2>/dev/null && {
    command -v "$_shell"
    return 0
  }

  [ -r "/proc/$$/exe" ] && readlink -f "/proc/$$/exe" && return 0

  [ -x "$SHELL" ] && printf '%s\n' "$SHELL" && return 0

  return 1
}

install_nix() {
  log_info "Nix not found. Installing via nixos.org/nix/install --no-daemon..."

  if ! command -v curl >/dev/null 2>&1; then
    if command -v apt >/dev/null 2>&1; then
      log_error "curl is required. Install it with: sudo apt update && sudo apt install -y curl"
    elif command -v pacman >/dev/null 2>&1; then
      log_error "curl is required. Install it with: sudo pacman -S curl"
    else
      log_error "curl is required. Install it with your system package manager."
    fi
    exit 1
  fi

  NIX_INSTALL="$(mktemp)"
  trap 'rm -f "$NIX_INSTALL"' EXIT

  if ! curl -sSfL https://nixos.org/nix/install -o "$NIX_INSTALL"; then
    log_error "Failed to download Nix installer."
    exit 1
  fi

  if [ "$(id -u)" -eq 0 ] && ! [ -d /nix ]; then
    log_info "Running as root, creating /nix manually..."
    mkdir -p /nix
  fi

  if ! sh "$NIX_INSTALL" --no-daemon; then
    log_error "Nix installer failed."
    exit 1
  fi

  NIX_CONF_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/nix"
  mkdir -p "$NIX_CONF_DIR"
  NIX_CONF="${NIX_CONF_DIR}/nix.conf"
  if ! grep -q 'build-users-group' "$NIX_CONF" 2>/dev/null; then
    printf 'build-users-group =\nextra-experimental-features = nix-command flakes\n' >> "$NIX_CONF"
    log_info "Patched nix.conf: disabled build-users-group."
  fi

  log_info "Nix installed successfully."
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [ -f "$NIX_HOOK" ]; then
  . "$NIX_HOOK"
fi

if ! command -v nix >/dev/null 2>&1; then
  install_nix
  if [ -f "$NIX_HOOK" ]; then
    . "$NIX_HOOK"
  fi
  if ! command -v nix >/dev/null 2>&1; then
    log_error "Nix binary still not found after installation. Try opening a new terminal."
    exit 1
  fi
else
  log_info "Nix is already installed -- skipping installation."
fi

CURR_SHELL="$(detect_shell)"
log_info "Entering dev shell (nix develop) with shell: ${CURR_SHELL}..."
log_info "Repository: ${REPO_ROOT}"

exec nix --extra-experimental-features 'nix-command flakes' \
  develop "${REPO_ROOT}" \
  -c "$CURR_SHELL"
