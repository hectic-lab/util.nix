{ lib, writeShellScriptBin, fetchFromGitHub }: let
  src = fetchFromGitHub {
    owner = "nativerv";
    repo = "slpt";
    rev = "8d70db4d8dfcd624ed49b9e6fb0ad449b6f25b89";
    hash = "sha256-sCHZsf7Y36iAesh7BeSxy9WhE/uQv13/VWmjlaVSEcU=";
  };
in writeShellScriptBin "slpt" (builtins.readFile "${src}/slpt")
