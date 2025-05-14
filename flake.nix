{
  description = "yukkop's nix utilities";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
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
    nixpkgs-unstable,
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
      pkgs-unstable = import nixpkgs-unstable { inherit system; };
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
        c-hectic = pkgs.callPackage ./package/c/hectic/default.nix {};
        watch = pkgs.callPackage ./package/c/watch/default.nix {};
        hmpl = pkgs.callPackage ./package/c/hmpl/default.nix { 
          hectic = self.packages.${system}.hectic;
        };
      };

      devShells.${system} = let
        shells = self.devShells.${system};
      in {
        c = pkgs.mkShell {
          buildInputs = (with pkgs; [ inotify-tools gdb gcc ]) ++ (with self.packages.${system}; [ c-hectic nvim-pager watch ]);
          PAGER = "${self.packages.${system}.nvim-pager}/bin/pager";
        };
	postgres-c = pkgs.mkShell {
          buildInputs = (with pkgs; [ inotify-tools postgresql_15 ]) ++ (with self.packages.${system}; [ nvim-pager ]) ++ (with pkgs-unstable; [ gdb gcc ]);
          PAGER = "${self.packages.${system}.nvim-pager}/bin/pager";

	  shellHook = ''
            export PATH=${pkgs-unstable.gcc}/bin:$PATH
            export PAGER="${self.packages.${system}.nvim-pager}/bin/pager"
          '';
        };
	pure-c = pkgs.mkShell {
          buildInputs = (with pkgs; [ inotify-tools ]) ++ (with self.packages.${system}; [ nvim-pager ]) ++ (with pkgs-unstable; [ gdb gcc binutils ]);
          PAGER = "${self.packages.${system}.nvim-pager}/bin/pager";

	  shellHook = ''
            export PATH=${pkgs-unstable.gcc}/bin:$PATH
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

              programs.zsh.shellAliases = self.lib.sharedShellAliases;

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

		  -- SELECT hemar.parse('{% zalupa %}');
		  SELECT hemar.render('{"a": "b"}'::JSONB, 'a {% a %}');
		  SELECT hemar.render('{"a": ["b", "c"]}'::JSONB, 'a {% for i in a do text %}');
		  SELECT hemar.render('{"a": {"g": ["b", "c"]}}'::JSONB, 'a {% for i in a.g do {% i %} %}');
		  SELECT hemar.render('{"a": {"g": ["b", "c"], "b": [{"c": "a"}, {"c": "b"}]}}'::JSONB, 'a {% for i in a.b do {% i.c %} %}');
                '';
              };                   
 
              environment.systemPackages =  with pkgs; [ gdb ];
              programs.zsh.shellAliases = self.lib.sharedShellAliases // {
	        conn = "sudo su postgres -c 'psql -p 64317'";
	        check = "journalctl -u postgresql";
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
        "hardware.hetzner" = {...}: {
          boot.loader.grub.device = "/dev/sda";
          boot.initrd.availableKernelModules = [
            "ata_piix"
            "uhci_hcd"
            "xen_blkfront"
            "vmw_pvscsi"
          ];
          boot.initrd.kernelModules = ["nvme"];
          fileSystems."/" = {
            device = "/dev/sda1";
            fsType = "ext4";
          };
        };
      };
      overlays.default = final: prev: (
        let
          pkgs-unstable = import nixpkgs-unstable { inherit (prev) system; };

          buildPgrxExtension =
            prev.callPackage (import (builtins.path {
              name = "extension-builder";
              path = ./buildPgrxExtension.nix;
            })) { 
              cargo-pgrx = pkgs-unstable.cargo-pgrx_0_12_6;
              inherit (pkgs-unstable.darwin.apple_sdk.frameworks) Security;
            };

          buildPostgresqlExtension =
            prev.callPackage (import (builtins.path {
              name = "extension-builder";
              path = ./buildPostgresqlExtension.nix;
            }));

          buildSmtpExt = versionSuffix: let
            postgresql = prev."postgresql_${versionSuffix}";
            src = prev.fetchFromGitHub {
              owner = "brianpursley";
              repo = "pg_smtp_client";
              rev = "6ff3b71e3705e0d4081a51c21ca0379e869ba5fb";
              hash = "sha256-wC/2rAsSDO83UITaFhtaf3do3aaOAko4gnKUOzwURc8=";
            };
            cargo = self.lib.cargoToml src;
          in
            buildPgrxExtension {
              pname = cargo.package.name;
              version = cargo.package.version;
          
              inherit src postgresql;
          
              buildInputs = with prev; [ openssl ];

              cargoHash = "sha256-AbLT7vcFV89zwZIaTC1ELat9l4UeNP8Bn9QMMOms1Co=";
          
              doCheck = false;
            };
          buildPlHaskellExt = versionSuffix: let
	      version = "4.0"; 
            in buildPostgresqlExtension {
              postgresql = prev."postgresql_${versionSuffix}";
            } {
              pname = "plhaskell";
              inherit version;
              src = prev.fetchFromGitHub {
                owner = "ed-o-saurus";
                repo = "PLHaskell";
                rev = "d917f0991a455cf0558c2036e360ba1a9b40a8ef";
                hash = "sha256-+sJmR/SCMfxxExa7GZuNmWez1dfhvlM9qOdO9gHNf74=";
              };
              nativeBuildInputs = with prev; [pkg-config curl ghc haskellPackages.hsc2hs haskellPackages.HSFFIG];
            };
          buildHttpExt = versionSuffix: let
              version = "1.6.1";
            in buildPostgresqlExtension {
              postgresql = prev."postgresql_${versionSuffix}";
            } {
              pname = "http";
              inherit version;
              src = prev.fetchFromGitHub {
	        owner = "pramsey";
		repo = "pgsql-http";
		rev = "v${version}";
		hash = "sha256-C8eqi0q1dnshUAZjIsZFwa5FTYc7vmATF3vv2CReWPM=";
	    };
	    nativeBuildInputs = with prev; [pkg-config curl];
	  };
          buildHemarExt = versionSuffix: let
              postgresql = prev."postgresql_${versionSuffix}";
	      c-hectic = self.packages.${prev.system}.c-hectic;
	  in buildPostgresqlExtension {
              inherit postgresql;
            } {
              pname = "hemar";
              version = "0.1";
              src = ./package/c/hemar;
              nativeBuildInputs = (with prev; [pkg-config]) ++ [ c-hectic ];
	      dontShrinkRPath = true;
	      postFixup = ''
	        echo ">>> postFixup running..."
                ${prev.patchelf}/bin/patchelf --set-rpath ${c-hectic}/lib $out/lib/hemar.so
              '';
              preInstall = ''mkdir $out'';
            };
        in {
          hectic = self.packages.${prev.system};
          postgresql_17 = prev.postgresql_17 // {pkgs = prev.postgresql_17.pkgs // {
            http = buildHttpExt "17";
            pg_smtp_client = buildSmtpExt "17";
            plhaskell = buildPlHaskellExt "17";
            hemar = buildHemarExt "17";
          };};
          postgresql_16 = prev.postgresql_16 // {pkgs = prev.postgresql_16.pkgs // {
            http = buildHttpExt "16";
            pg_smtp_client = buildSmtpExt "16";
            plhaskell = buildPlHaskellExt "16";
            hemar = buildHemarExt "16";
          };};
          postgresql_15 = prev.postgresql_15 // {pkgs = prev.postgresql_15.pkgs // {
            http = buildHttpExt "15";
            pg_smtp_client = buildSmtpExt "15";
            plhaskell = buildPlHaskellExt "15";
            hemar = buildHemarExt "15";
          };};
          postgresql_14 = prev.postgresql_14 // {pkgs = prev.postgresql_14.pkgs // {
            http = buildHttpExt "14";
            pg_smtp_client = buildSmtpExt "14";
            plhaskell = buildPlHaskellExt "14";
            hemar = buildHemarExt "14";
          };};
          writers = let
            writeC =
              name: argsOrScript:
              if lib.isAttrs argsOrScript && !lib.isDerivation argsOrScript then
                prev.writers.makeBinWriter (
                  argsOrScript // {
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
                ) name
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
                } name argsOrScript;
            writeMinC =
              name: includes: body:
                writeC name ''
                  ${builtins.concatStringsSep "\n" (map (h: "#include " + h) includes)}

                  int main(int argc, char *argv[]) {
                      ${body}
                  }
                '';
          in prev.writers // {
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
