{ lib, writeShellScriptBin, fetchFromGitHub, pkgs }: let
  src = fetchFromGitHub {
    owner = "nativerv";
    repo = "slpt";
    rev = "8d70db4d8dfcd624ed49b9e6fb0ad449b6f25b89";
    hash = "sha256-sCHZsf7Y36iAesh7BeSxy9WhE/uQv13/VWmjlaVSEcU=";
  };
in writeShellScriptBin "slpt" ''
  #!${pkgs.runtimeShell}
  PATH=${lib.makeBinPath [ pkgs.jq ]}:$PATH
  ${builtins.readFile "${src}/slpt"}
''
