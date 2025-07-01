{ lib, writeShellScriptBin, fetchFromGitHub }: let
  src = fetchFromGitHub {
    owner = "nativerv";
    repo = "slpt";
    rev = "6ce04bcf53e12518eb7abba193c72014557ec2c2";
    hash = "sha256-AZ8z8wR8xX9tYNM9sPb0Uqc0UHWebMbal8sNupWAbOI=";
  };
in writeShellScriptBin "slpt" (builtins.readFile "${src}/slpt")
