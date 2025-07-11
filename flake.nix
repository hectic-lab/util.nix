{
  description = "yukkop's nix utilities";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };
  };

  outputs = {
    self,
    nixpkgs,
    rust-overlay,
  }: let
    lib = nixpkgs.lib;

    recursiveUpdate = lib.recursiveUpdate;

    supportedSystems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin"];

    forSpecSystemsWithPkgs = supportedSystems: pkgOverlays: f:
      builtins.foldl' (
        acc: system: let
          pkgs = import nixpkgs {
            inherit system;
            overlays = pkgOverlays;
          };
          systemOutputs = f {
            system = system;
            pkgs = pkgs;
          };
        in
          recursiveUpdate acc systemOutputs
      ) {}
      supportedSystems;

    forAllSystemsWithPkgs = pkgOverlays: f: forSpecSystemsWithPkgs supportedSystems pkgOverlays f;

    envErrorMessage = varName: "Error: The ${varName} environment variable is not set.";

    parseEnv = import ./parse-env.nix;

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
      cargo = self.lib.cargoToml src;
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

    dotEnv = builtins.getEnv "DOTENV";
    minorEnvironment =
      if dotEnv != ""
      then
        if builtins.pathExists dotEnv
        then parseEnv dotEnv
        else throw "${dotEnv} file not exist"
      else if builtins.pathExists ./.env
      then parseEnv ./.env
      else {};
  in
    forAllSystemsWithPkgs [(import rust-overlay)] ({
      system,
      pkgs,
    }: let
    in {
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
        "${system}_manual_test" = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            self.nixosModules."preset.default"
            self.nixosModules."hardware.hetzner"
            ({modulesPath, pkgs, ...}: {
              imports = [
                (modulesPath + "/profiles/qemu-guest.nix")
              ];

              environment.systemPackages = with pkgs; [
                (pkgs.writers.writeMinCBin "minc-hello-world" ["<stdio.h>"] /*c*/ ''
                  printf("hello world\n");
                '')
                (pkgs.writers.writeMinCBin "minc-env" ["<stdio.h>" "<stdlib.h>"] /*c*/ ''
                  char *env_name;
                  if (argc > 1) {
                    env_name = argv[1];
                  } else {
                    env_name = "HOME";
                  }
                  char *value = getenv(env_name);
                  if (value) {
                      printf("%s: %s\n", env_name, value);
                  } else {
                      printf("Environment variable %s not found.\n", env_name);
                  }
                '')
                (pkgs.writers.writeMinCBin "minc-env-check" ["<stdio.h>" "<stdlib.h>"] /*c*/ ''
                  char *env_name;
                  if (argc > 1) {
                    env_name = argv[1];
                  } else {
                    env_name = "HOME";
                  }

                  char *value = getenv(env_name);
                  if (value) {
                      char buffer[128];
                      sprintf(buffer, "echo $%s\n", env_name);
                      system(buffer);
                  } else {
                      printf("Environment variable %s not found.\n", env_name);
                  }
                '')
              ];

              users.users.root.openssh.authorizedKeys.keys = [
                ''ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICrbBG+U07f7OKvOxYIGYCaNvyozzxQF+I9Fb5TYZErK yukkop vm-postgres''
              ];

              programs.zsh.shellAliases = self.lib.sharedShellAliasesForDevVm;

              virtualisation = {
                vmVariant = {
                  systemd.services.fix-root-perms = {
                    description = "Fix root directory permissions";
                    after = [ "local-fs.target" ];
                    wantedBy = [ "multi-user.target" ];
                    serviceConfig = {
                      Type = "oneshot";
                      ExecStart = "${pkgs.coreutils}/bin/chmod 755 /";
                    };
                  };
                  virtualisation = {
                    diskSize = 1024*6;
                    diskImage = null;
                    forwardPorts = [ ];
                  };
                };
              };
              networking.firewall = {
                enable = true;
                allowedTCPPorts = [
                  80
                ];
              };
            })
          ];
          pkgs = import nixpkgs {inherit system; overlays = [ self.overlays.default ];};
        };
        "${system}_hemar_test" = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            self.nixosModules."preset.default"
            self.nixosModules."hardware.hetzner"
            ({modulesPath, pkgs, ...}: {
              imports = [
                (modulesPath + "/profiles/qemu-guest.nix")
              ];

              users.users.root.openssh.authorizedKeys.keys = [
                ''ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICrbBG+U07f7OKvOxYIGYCaNvyozzxQF+I9Fb5TYZErK yukkop vm-postgres''
              ];



              services.postgresql =
              let
                package = pkgs.postgresql_15;
              in {
                enable = true;
                package = package;
                settings = 
                {
                  port = 64317;
                  listen_addresses = lib.mkForce "*";
                  shared_preload_libraries = "";
                };
                extensions = [ package.pkgs.hemar ];
                authentication =  builtins.concatStringsSep "\n" [
                  "local all       all     trust"
                  "host  sameuser    all     127.0.0.1/32 scram-sha-256"
                  "host  sameuser    all     ::1/128 scram-sha-256"
                ];
                initialScript = pkgs.writeText "init-sql-script" ''
                  SET log_min_messages TO DEBUG1;
                  SET client_min_messages TO DEBUG1;
                  ALTER DATABASE postgres SET log_min_messages TO DEBUG1;
                  ALTER DATABASE postgres SET client_min_messages TO DEBUG1;
                  CREATE EXTENSION "hemar";

                  \i ${./package/c/hemar/test}/mod.sql
                '';
              };                   
 
              environment.systemPackags =  with pkgs; [
                gdb
                hectic.nvim-pager
                (writeScriptBin "check" ''
                  journalctl -u postgresql.service | grep postgresql-post-start | sed 's|psql:/nix/store/[^:]*:[0-9]*: ||' | sed 's|^[^:]*:[^:]*:[^:]*: ||' | grep -v '^\[.*\]' | ${hectic.prettify-log}/bin/prettify-log --color-output
                '')
               ];
              programs.zsh.shellAliases = self.lib.sharedShellAliasesForDevVm // {
                conn = "sudo su postgres -c 'psql -p 64317'";
              };

              virtualisation = {
                vmVariant = {
                  systemd.services.fix-root-perms = {
                    description = "Fix root directory permissions";
                    after = [ "local-fs.target" ];
                    wantedBy = [ "multi-user.target" ];
                    serviceConfig = {
                      Type = "oneshot";
                      ExecStart = "${pkgs.coreutils}/bin/chmod 755 /";
                    };
                  };
                  virtualisation = {
                    diskSize = 1024*6;
                    diskImage = null;
                    forwardPorts = [ ];
                  };
                };
              };
              networking.firewall = {
                enable = true;
                allowedTCPPorts = [
                  80
                ];
              };
            })
          ];
          pkgs = import nixpkgs {inherit system; overlays = [ self.overlays.default ];};
        };
      };
    })
    // {
      nixosModules = {
        "preset.default" = {
          pkgs,
          modulesPath,
          ...
        }: {
          imports = [
            (modulesPath + "/profiles/qemu-guest.nix")
          ];

          services.getty.autologinUser = "root";
          programs.zsh.shellAliases = self.lib.sharedShellAliases;

          programs.zsh.enable = true;
          users.defaultUserShell = pkgs.zsh;

          # Enable flakes and new 'nix' command
          nix.settings.experimental-features = "nix-command flakes";

          virtualisation.vmVariant.virtualisation = {
            qemu.options = [
              "-nographic"
              "-display curses"
              "-append console=ttyS0"
              "-serial mon:stdio"
              "-vga qxl"
            ];
            forwardPorts = [
              {
                from = "host";
                host.port = 40500;
                guest.port = 22;
              }
            ];
          };

          services.openssh = {
            enable = true;
            settings = {
              PasswordAuthentication = false;
            };
          };

          networking.firewall = {
            enable = true;
            allowedTCPPorts = [];
          };

          environment = {
            defaultPackages = [];
            systemPackages =
              (with pkgs; [
                curl
                neovim
                yq-go
                jq
                htop-vim
              ])
              ++ (with self.packages.${pkgs.system}; [
                prettify-log
                nvim-pager
              ]);
            variables = {
              PAGER = with self.packages.${pkgs.system}; "${nvim-pager}/bin/pager";
            };
          };

          system.stateVersion = "24.11";
        };
        "hardware.hetzner" = { pkgs, ...}: {
          boot.loader.grub.device = "/dev/sda";
          boot.initrd.availableKernelModules = [
            "ata_piix"
            "uhci_hcd"
            "xen_blkfront"
          ] ++ (if pkgs.system != "aarch64-linux" then [ "vmw_pvscsi" ] else []);
          boot.initrd.kernelModules = ["nvme"];
          fileSystems."/" = {
            device = "/dev/sda1";
            fsType = "ext4";
          };
        };
      };
      overlays.default = final: prev: (
        let
	  hectic-packages = self.packages.${prev.system};
        in {
          hectic = hectic-packages;
          postgresql_17 = prev.postgresql_17 // {pkgs = prev.postgresql_17.pkgs // {
            http = hectic-packages.pg-17-ext-http;
            pg_smtp_client = hectic-packages.pg-17-ext-smtp-client;
            plhaskell = hectic-packages.pg-17-ext-plhaskell;
            plsh = hectic-packages.pg-17-ext-plsh;
            hemar = hectic-packages.pg-17-ext-hemar;
          };};
          postgresql_16 = prev.postgresql_16 // {pkgs = prev.postgresql_16.pkgs // {
            http = hectic-packages.pg-16-ext-http;
            pg_smtp_client = hectic-packages.pg-16-ext-smtp-client;
            plhaskell = hectic-packages.pg-16-ext-plhaskell;
            plsh = hectic-packages.pg-16-ext-plsh;
            hemar = hectic-packages.pg-16-ext-hemar;
          };};
          postgresql_15 = prev.postgresql_15 // {pkgs = prev.postgresql_15.pkgs // {
            http = hectic-packages.pg-15-ext-http;
            pg_smtp_client = hectic-packages.pg-15-ext-smtp-client;
            plhaskell = hectic-packages.pg-15-ext-plhaskell;
            plsh = hectic-packages.pg-15-ext-plsh;
            hemar = hectic-packages.pg-15-ext-hemar;
          };};
          writers = let
            writeC = name: argsOrScript:
              if lib.isAttrs argsOrScript && !lib.isDerivation argsOrScript
              then
                prev.writers.makeBinWriter (
                  argsOrScript
                  // {
                    compileScript = ''
                      # Force gcc to treat the input file as C code
                      ${prev.gcc}/bin/gcc -fsyntax-only -xc $contentPath
                      if [ $? -ne 0 ]; then
                        echo "Syntax check failed"
                        exit 1
                      fi
                      ${prev.gcc}/bin/gcc -xc -o $out $contentPath
                    '';
                  }
                )
                name
              else
                prev.writers.makeBinWriter {
                  compileScript = ''
                    # Force gcc to treat the input file as C code
                    ${prev.gcc}/bin/gcc -fsyntax-only -xc $contentPath
                    if [ $? -ne 0 ]; then
                      echo "Syntax check failed"
                      exit 1
                    fi
                    ${prev.gcc}/bin/gcc -xc -o $out $contentPath
                  '';
                }
                name
                argsOrScript;
            writeMinC = name: includes: body:
              writeC name ''
                ${builtins.concatStringsSep "\n" (map (h: "#include " + h) includes)}

                int main(int argc, char *argv[]) {
                    ${body}
                }
              '';
          in
            prev.writers
            // {
              writeCBin = name: writeC "/bin/${name}";
              writeC = writeC;
              writeMinCBin = name: includes: body: writeMinC "/bin/${name}" includes body;
              writeMinC = writeMinC;
            };
        }
      );
      lib = {
        # -- For all systems --
        inherit dotEnv minorEnvironment parseEnv forAllSystemsWithPkgs forSpecSystemsWithPkgs;

        sharedShellAliases = {
          jc = ''journalctl'';
          sc = ''journalctl'';
          nv = ''nvim'';
        };

        sharedShellAliasesForDevVm = self.lib.sharedShellAliases // {
          sd = "shutdown now";
        };

        readEnvironment = { envVarsToRead, prefix ? "" }:
          builtins.listToAttrs
          (map (name: {
              inherit name;
              value = self.lib.getEnv "${prefix}${name}";
            })
            envVarsToRead);

        # -- Env processing --
        getEnv = varName: let
          var = builtins.getEnv varName;
        in
          if var != ""
          then var
          else if minorEnvironment ? varName
          then minorEnvironment."${varName}"
          else throw (envErrorMessage varName);

        # -- Cargo.toml --
        cargoToml = src: (builtins.fromTOML (builtins.readFile "${src}/Cargo.toml"));

        ssh.keys = {
          hetzner-test = {
            yukkop = ''ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ8scy1tv6zfXX6xyaukhO/fsZwif5rC89DvXNc6XxOf'';
          };
        };
      };
    };
}
