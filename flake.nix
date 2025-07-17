{
  description = "yukkop's nix utilities";
  inputs = {
    nixpkgs-25-05.url = "github:NixOS/nixpkgs/nixos-25.05";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs = {
        nixpkgs.follows = "nixpkgs-25-05";
      };
    };
  };

  outputs = {
    self,
    nixpkgs-25-05,
    rust-overlay,
    ...
  }@inputs: let
    flake = ./.;
    nixpkgs = nixpkgs-25-05;
    overlays = [ self.overlays.default ];
    self-lib = import ./lib { inherit flake self inputs nixpkgs; };
  in
    self-lib.forAllSystemsWithPkgs [(import rust-overlay)] ({
      system,
      pkgs,
    }: {
      packages.${system} = import ./package { inherit system pkgs self; };

      devShells.${system} = {
        c = import ./devshell/c.nix { inherit self system pkgs; };
        postgres-c = import ./devshell/postgres-c.nix { inherit self system pkgs; };
        pure-c = import ./devshell/pure-c.nix { inherit self system pkgs; };
        default = import ./devshell/default.nix { inherit self system pkgs; };
        rust = import ./devshell/rust.nix { inherit self system pkgs; };
        haskell = import ./devshell/haskell.nix { inherit self system pkgs; };
      };
      nixosConfigurations = {
        "devvm-manual|${system}" = import ./nixos/system/devvm-manual/default.nix { inherit flake self inputs system; };
        "devvm-hemar|${system}" = import ./nixos/system/devvm-hemar/default.nix { inherit flake self inputs system; };
      };
    }) //
  {
    legacyPackages = self.lib.forAllSystems (system: import nixpkgs {
        inherit system overlays;
    });

    lib = self-lib;
    overlays.default = import ./overlay { inherit flake self inputs nixpkgs; };
    nixosModules = import ./nixos/module { inherit flake self inputs nixpkgs; };
  };
}
