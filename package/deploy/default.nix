{ inputs, symlinkJoin, dash, hectic, ssh-to-age, system }:
let
  shell = "${dash}/bin/dash";
  bashOptions = [
    "errexit"
    "nounset"
  ];

  deploy = hectic.writeShellApplication {
    inherit shell bashOptions;
    name = "deploy";
    runtimeInputs = [ 
      ssh-to-age
      inputs.nixos-anywhere.packages.${system}.nixos-anywhere
    ];

    text = builtins.readFile ./deploy.sh;
  };
in
symlinkJoin {
  name = "deploy";
  paths = [ deploy ];
}
