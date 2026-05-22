{ dash, hectic, git, gnutar, gzip, bzip2, xz, unzip, coreutils, file }:
let
  shell = "${dash}/bin/dash";
in
hectic.writeShellApplication {
  inherit shell;
  bashOptions = [
    "errexit"
    "nounset"
  ];
  excludeShellChecks = [ "SC2209" ];
  name = "merge-archive";
  runtimeInputs = [ git gnutar gzip bzip2 xz unzip coreutils file ];

  text = ''
    ${builtins.readFile hectic.helpers.posix-shell.log}
    ${builtins.readFile hectic.helpers.posix-shell.pager_or_cat}
    ${builtins.readFile ./merge-archive.sh}
  '';

  meta = {
    description = "Merge an archive into a git repository with --allow-unrelated-histories";
    mainProgram = "merge-archive";
  };
}
