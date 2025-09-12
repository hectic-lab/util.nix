{
  sops,
  pkgs,
  lib,
  ...
}: let
  scriptOverride = pkgs.writeShellScriptBin "sops" ''
    set -uo pipefail

    if [ -n "''${SOPS_AGE_KEY_COMMAND:-}" ]; then
      dir="$(mktemp -d)"
      chmod 700 "''${dir}"
      export SOPS_AGE_KEY_FILE="$(mktemp --tmpdir="$dir")"
      chmod 600 "''${SOPS_AGE_KEY_FILE}"
      trap 'rm -f "''${SOPS_AGE_KEY_FILE}"' INT TERM EXIT
      sh -c "''${SOPS_AGE_KEY_COMMAND}" > "''${SOPS_AGE_KEY_FILE}"
    else
      printf >&2 'sops (wrapper): ERROR: environment variable `SOPS_AGE_KEY_COMMAND` is empty or undefined\n'
      printf >&2 'sops (wrapper): INFO: `SOPS_AGE_KEY_COMMAND` must contain a command that prints `age` private key\n'
      printf >&2 'sops (wrapper): INFO: example: `pass show sops/myproject/key` (see https://www.passwordstore.org/)\n'
      exit 1
    fi
    ${sops}/bin/sops "''${@}"
  '';
in pkgs.symlinkJoin {
  name = "sops-wrapper";
  paths = [ scriptOverride sops ];
  buildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    set -x
    for bin in $out/bin/*; do
      wrapProgram "$bin" \
        --prefix PATH : ${lib.makeBinPath (with pkgs; [
          coreutils
        ])} \
        --suffix PATH : ${lib.makeBinPath (with pkgs; [
          age # expected to be used by ${SOPS_AGE_KEY_COMMAND}
        ])}
    done
  '';

  meta = sops.meta // {
    description = "${sops.meta.description} -- wrapper. Provides custom source for `age` master key.";
  };
}
