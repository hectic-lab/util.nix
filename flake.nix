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

      devShells.${system} = let
        shells = self.devShells.${system};
      in {
        c = pkgs.mkShell {
          buildInputs = (with pkgs; [inotify-tools gdb gcc]) ++ (with self.packages.${system}; [c-hectic nvim-pager watch]);
          PAGER = "${self.packages.${system}.nvim-pager}/bin/pager";
        };
        postgres-c = pkgs.mkShell {
          buildInputs = (with pkgs; [ inotify-tools postgresql_15 ]) ++ (with self.packages.${system}; [ nvim-pager ]) ++ (with pkgs; [ gdb gcc ]);
          PAGER = "${self.packages.${system}.nvim-pager}/bin/pager";

          shellHook = ''
            export PATH=${pkgs.gcc}/bin:$PATH
            export PAGER="${self.packages.${system}.nvim-pager}/bin/pager"
          '';
        };
        pure-c = pkgs.mkShell {
          buildInputs = (with pkgs; [ inotify-tools ]) ++ (with self.packages.${system}; [ nvim-pager ]) ++ (with pkgs; [ gdb gcc binutils ]);
          PAGER = "${self.packages.${system}.nvim-pager}/bin/pager";

          shellHook = ''
            export PATH=${pkgs.gcc}/bin:$PATH

            export PAGER="${self.packages.${system}.nvim-pager}/bin/pager"
          '';
        };
        default = pkgs.mkShell {
          buildInputs =
            (with self.packages.${system}; [
              nvim-alias
              #prettify-log
              nvim-pager
            ])
            ++ (with pkgs; [
              git
              jq
              yq-go
              curl
              (writeScriptBin "hemar-check" ''
                ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null vm-postgres 'zsh -c check'
              '')
            ]);

          # environment
          PAGER = "${self.packages.${system}.nvim-pager}/bin/pager";
        };
        rust = let
          rustToolchain =
            if builtins.pathExists ./rust-toolchain.toml
            then pkgs.pkgsBuildHost.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml
            else pkgs.pkgsBuildHost.rust-bin.stable."1.81.0".default;
        in
          shells.default
          // (pkgs.mkShell {
            nativeBuildInputs = [
              rustToolchain
              pkgs.pkg-config
            ];
          });
        haskell =
          shells.default
          // (pkgs.mkShell {
            buildInputs = [pkgs.stack];
          });
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
