# necessary to load every time .nvimrc
# makes some magic to shading nvim but still uses nvim that shaded
{pkgs, ...}:
pkgs.writeShellScriptBin "nvim" ''
  # Source .env file
  if [ -f .env ]; then
      set -a
      . .env
      set +a
  fi

  # Get the directory of this script
  SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

  # Remove the script's directory from PATH to avoid recursion
  PATH=$(echo "$PATH" | tr ':' '\n' | grep -v "$SCRIPT_DIR" | paste -sd ':' -)

  # Find the system's nvim
  SYSTEM_NVIM=$(command -v nvim)

  if [ -z "$SYSTEM_NVIM" ]; then
    echo "Error: nvim not found in PATH" >&2
    exit 1
  fi

  # Execute the system's nvim with your custom arguments
  exec "$SYSTEM_NVIM" --cmd 'lua vim.o.exrc = true' "$@"
''
