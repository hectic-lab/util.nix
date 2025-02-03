{ pkgs, ... }: 
pkgs.writeShellScriptBin "supabase" ''
# Get the root of the repository
GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo .)"

# Source .env from root of the repo if it exists
if [ -f "$GIT_ROOT/.env" ]; then
  set -a
  . "$GIT_ROOT/.env"
  set +a
fi

${pkgs.supabase-cli}/bin/supabase --workdir "$GIT_ROOT/web" $@
''
