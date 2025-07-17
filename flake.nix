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

    buildPostgresqlExtension =
      pkgs: pkgs.callPackage (import (builtins.path {
        name = "extension-builder";
        path = ./buildPostgresqlExtension.nix;
      }));

    buildHemarExt = pkgs: versionSuffix: let
        postgresql = pkgs."postgresql_${versionSuffix}";
        c-hectic = self.packages.${pkgs.system}.c-hectic;
    in buildPostgresqlExtension pkgs {
        stdenv = pkgs.clangStdenv;
        inherit postgresql;
      } {
        pname = "hemar";
        version = "0.1";
        src = ./package/c/hemar;
        nativeBuildInputs = (with pkgs; [pkg-config]) ++ [ c-hectic ];
        dontShrinkRPath = true;
        postFixup = ''
          echo ">>> postFixup running..."
          ${pkgs.patchelf}/bin/patchelf --set-rpath ${c-hectic}/lib $out/lib/hemar.so
        '';
        preInstall = ''mkdir $out'';
      };
    buildPgrxExtension = pkgs: 
      pkgs.callPackage (import (builtins.path {
        name = "extension-builder";
        path = ./buildPgrxExtension.nix;
      })) { 
        cargo-pgrx = pkgs.cargo-pgrx_0_12_6;
        inherit (pkgs.darwin.apple_sdk.frameworks) Security;
      };

    buildSmtpExt = pkgs: versionSuffix: let
      postgresql = pkgs."postgresql_${versionSuffix}";
      src = pkgs.fetchFromGitHub {
        owner = "brianpursley";
        repo = "pg_smtp_client";
        rev = "6ff3b71e3705e0d4081a51c21ca0379e869ba5fb";
        hash = "sha256-wC/2rAsSDO83UITaFhtaf3do3aaOAko4gnKUOzwURc8=";
      };
      cargo = self-lib.cargoToml src;
    in
      buildPgrxExtension pkgs {
        pname = cargo.package.name;
        version = cargo.package.version;
    
        inherit src postgresql;
    
        buildInputs = with pkgs; [ openssl ];

        cargoHash = "sha256-Cg5qY4TKkSJRSAtlFbjIRhea0dXPLEyasi5n09HcYeo=";
    
        doCheck = false;
      };
    buildPlShExt = pkgs: versionSuffix: let
        version = "4.0"; 
      in buildPostgresqlExtension pkgs {
        stdenv = pkgs.clangStdenv;
        postgresql = pkgs."postgresql_${versionSuffix}";
      } {
        pname = "plsh";
        inherit version;
        src = pkgs.fetchFromGitHub {
          owner = "petere";
          repo = "plsh";
          rev = "d88079617309974f71b3f8e4d5f96869dba66835";
          hash = "sha256-H9B5L+yIjjVNhnuF+bIZKyCrOqfIvu5W26aqyqL5UdQ=";
        };
        nativeBuildInputs = with pkgs; [ pkg-config ];
      };
    buildPlHaskellExt = pkgs: versionSuffix: let
        version = "4.0"; 
      in buildPostgresqlExtension pkgs {
        stdenv = pkgs.clangStdenv;
        postgresql = pkgs."postgresql_${versionSuffix}";
      } {
        pname = "plhaskell";
        inherit version;
        src = pkgs.fetchFromGitHub {
          owner = "ed-o-saurus";
          repo = "PLHaskell";
          rev = "d917f0991a455cf0558c2036e360ba1a9b40a8ef";
          hash = "sha256-+sJmR/SCMfxxExa7GZuNmWez1dfhvlM9qOdO9gHNf74=";
        };
	preBuild = ''
	  last=$(pwd)
	  cd ${pkgs.haskellPackages.ghc}
	  include=$(dirname "${pkgs.haskellPackages.ghc}/$(find . -name HsFFI.h)")
	  ls $include
	  cd $last
          export NIX_CFLAGS_COMPILE="$NIX_CFLAGS_COMPILE -I$include"
        '';
        nativeBuildInputs = with pkgs; [
	  pkg-config
	  curl
	  ghc
	  haskellPackages.hsc2hs
	  haskellPackages.ghc 
	];
      };
    buildHttpExt = pkgs: versionSuffix: let
        version = "1.6.1";
      in buildPostgresqlExtension pkgs {
        stdenv = pkgs.clangStdenv;
        postgresql = pkgs."postgresql_${versionSuffix}";
      } {
        pname = "http";
        inherit version;
        src = pkgs.fetchFromGitHub {
          owner = "pramsey";
          repo = "pgsql-http";
          rev = "v${version}";
          hash = "sha256-C8eqi0q1dnshUAZjIsZFwa5FTYc7vmATF3vv2CReWPM=";
      };
      nativeBuildInputs = with pkgs; [pkg-config curl];
    };

  in
    self-lib.forAllSystemsWithPkgs [(import rust-overlay)] ({
      system,
      pkgs,
    }: {
      packages.${system} = let
        rust = {
          nativeBuildInputs = [
            pkgs.pkgsBuildHost.rust-bin.stable."1.81.0".default
            pkgs.pkg-config
          ];
          commonArgs = {
            inherit (self.lib) cargoToml;
            inherit (rust) nativeBuildInputs;
          };
        };
      in {
        py3-datetime = pkgs.python3Packages.buildPythonPackage rec {
          pname = "DateTime";
          version = "5.5";
          
          src = pkgs.fetchPypi {
            inherit pname version;
            sha256 = "sha256-IexjMfh6f8tXvXxZ6KaL//5vy/Ws27x7NW1qmgIBkdM=";
          };
        };
        py3-marzban = pkgs.python3Packages.buildPythonPackage rec {
          pname = "marzban";
          version = "0.4.3";
          
          src = pkgs.fetchPypi {
            inherit pname version;
            sha256 = "sha256-z71Wl4AuET3oES7/48u+paL9F12SdrkohcEee/tkWVk=";
          };

          format = "pyproject";
          
          propagatedBuildInputs = with pkgs.python3Packages; [
            httpx
            paramiko
            sshtunnel
          ];
          nativeBuildInputs = (with pkgs.python3Packages; [
            setuptools
            wheel
            setuptools-scm
            httpx
            pydantic
            paramiko
            sshtunnel
          ]) ++ (with self.packages.${system}; [
            py3-datetime
          ]);

          doCheck = false;
        };
        py3-asyncpayments = pkgs.python3Packages.buildPythonPackage rec {
          pname = "asyncpayments";
          version = "1.4.6";
          
          src = pkgs.fetchPypi {
            inherit pname version;
            sha256 = "sha256-t7AZiRb7DHZgJHPNQwAEuc0mrTQ14+82d19VomTjs8U=";
          };

          format = "pyproject";
          
          nativeBuildInputs = with pkgs.python3Packages; [ setuptools wheel setuptools-scm ];
          propagatedBuildInputs = with pkgs.python3Packages; [ aiohttp requests ];
          
          doCheck = false;
        };
        py3-payok = pkgs.python3Packages.buildPythonPackage rec {
          pname = "payok";
          version = "1.2";
          
          src = pkgs.fetchPypi {
            inherit pname version;
            sha256 = "sha256-UN+MSNGhrPpw7hZRLAx8XY3jC0ldo+DlbaSJ64wWBHo=";
          };
          
          propagatedBuildInputs = with pkgs.python3Packages; [ requests ];
          
          doCheck = false;
        };
        py3-asyncio = pkgs.python3Packages.buildPythonPackage rec {
          pname = "asyncio";
          version = "3.4.3";
          src = pkgs.python3Packages.fetchPypi {
            inherit pname version;
            sha256 = "sha256-gzYP+LyXmA5P8lyWTHvTkj0zPRd6pPf7c2sBnybHy0E=";
          };
        };
        py3-cryptomus = pkgs.python3Packages.buildPythonPackage rec {
          pname = "cryptomus";
          version = "1.1";
          src = pkgs.python3Packages.fetchPypi {
            inherit pname version;
            sha256 = "sha256-f0BBGfemKxMdz+LMvawWqqRfmF+TrCpMwgtJEYt+fgU=";
          };
        };
        py3-modulegraph = pkgs.python3Packages.buildPythonPackage rec {
          pname = "modulegraph";
          version = "0.19.6";
          src = pkgs.python3Packages.fetchPypi {
            inherit pname version;
            sha256 = "sha256-yRTIyVoOEP6IUF1OnCKEtOPbxwlD4wbMZWfjbMVBv0s=";
          };
        };
        py3-swifter = pkgs.python3Packages.buildPythonPackage rec {
          pname = "swifter";
          version = "1.4.0";
          src = pkgs.python3Packages.fetchPypi {
            inherit pname version;
            sha256 = "sha256-4bt0R2ohs/B6F6oYyX/cuoWZcmvRfacy8J2rzFDia6A=";
          };
        };
        py3-aiogram-newsletter = pkgs.python3Packages.buildPythonPackage rec {
          pname = "aiogram-newsletter";
          version = "0.0.10";

          src = pkgs.fetchFromGitHub {
            inherit pname version;
            owner = "nessshon";
            repo = "aiogram-newsletter";
            rev = "bb8a42e4bcff66a9a606fc92ccc27b1d094b20fc";
            sha256 = "sha256-atKhccp8Pr8anJUo+M9hnYkYrcgnB9SxrpmsiVusJZs=";
          };
        };
        nvim-alias = pkgs.callPackage ./package/nvim-alias.nix {};
        bolt-unpack = pkgs.callPackage ./package/bolt-unpack.nix {};
        nvim-pager = pkgs.callPackage ./package/nvim-pager.nix {};
        printobstacle = pkgs.callPackage ./package/printobstacle.nix {};
        printprogress = pkgs.callPackage ./package/printprogress.nix {};
        colorize = pkgs.callPackage ./package/colorize.nix {};
        github-gh-tl = pkgs.callPackage ./package/github/gh-tl.nix {};
        supabase-with-env-collection = pkgs.callPackage ./package/supabase-with-env-collection.nix {};
        migration-name = pkgs.callPackage ./package/migration-name.nix {};
        prettify-log = pkgs.callPackage ./package/prettify-log/default.nix rust.commonArgs;
        pg-from = pkgs.callPackage ./package/postgres/pg-from/default.nix rust.commonArgs;
        pg-schema = pkgs.callPackage ./package/postgres/pg-schema/default.nix rust.commonArgs;
        pg_wdumpall = pkgs.callPackage ./package/postgres/pg_wdumpall.nix rust.commonArgs; 
        pg_wdump = pkgs.callPackage ./package/postgres/pg_wdump.nix rust.commonArgs; 
        pg-migration = pkgs.callPackage ./package/postgres/pg-migration/default.nix rust.commonArgs;
        pg-17-ext-hemar = buildHemarExt pkgs "17";
        pg-17-ext-http = buildHttpExt pkgs "17";
        pg-17-ext-smtp-client = buildSmtpExt pkgs "17";
        pg-17-ext-plhaskell = buildPlHaskellExt pkgs "17";
        pg-17-ext-plsh = buildPlShExt pkgs "17";
        pg-16-ext-hemar = buildHemarExt pkgs "16";
        pg-16-ext-http = buildHttpExt pkgs "16";
        pg-16-ext-smtp-client = buildSmtpExt pkgs "16";
        pg-16-ext-plhaskell = buildPlHaskellExt pkgs "16";
        pg-16-ext-plsh = buildPlShExt pkgs "16";
        pg-15-ext-hemar = buildHemarExt pkgs "15";
        pg-15-ext-http = buildHttpExt pkgs "15";
        pg-15-ext-smtp-client = buildSmtpExt pkgs "15";
        pg-15-ext-plhaskell = buildPlHaskellExt pkgs "15";
        pg-15-ext-plsh = buildPlShExt pkgs "15";
        slpt = pkgs.callPackage ./package/slpt.nix {};
        c-hectic = pkgs.callPackage ./package/c/hectic/default.nix {};
        watch = pkgs.callPackage ./package/c/watch/default.nix {};
        support-bot = pkgs.callPackage ./package/support-bot {};
      };

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
