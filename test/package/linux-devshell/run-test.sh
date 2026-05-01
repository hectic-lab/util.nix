#!/bin/dash
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "Building standalone script..."
nix build "${REPO_ROOT}#linux-devshell-standalone" --no-link
STANDALONE_SCRIPT="$(nix build "${REPO_ROOT}#linux-devshell-standalone" --print-out-paths)"

echo "Standalone script built at: ${STANDALONE_SCRIPT}"

echo "Creating test repo..."
TEST_REPO="$(mktemp -d)"
trap 'rm -rf "$TEST_REPO"' EXIT

mkdir -p "${TEST_REPO}/script"
cp "$STANDALONE_SCRIPT" "${TEST_REPO}/script/linux-devshell"
chmod +x "${TEST_REPO}/script/linux-devshell"

cat > "${TEST_REPO}/flake.nix" <<'FLAKE'
{
  description = "Test flake for linux-devshell";

  outputs = { self, nixpkgs }: {
    devShells.default = nixpkgs.legacyPackages.x86_64-linux.mkShell {
      shellHook = ''
        echo "=== Inside dev shell ==="
        echo "This is a test dev shell"
        exit 0
      '';
    };
  };
}
FLAKE

echo "Test repo created at: ${TEST_REPO}"
echo ""
echo "Running linux-devshell in Arch Linux container..."

docker run --rm -it \
  -v "${TEST_REPO}:/test-repo:ro" \
  -w /test-repo \
  archlinux:latest \
  /test-repo/script/linux-devshell || {
    echo "Test completed (exit code: $?)"
  }
