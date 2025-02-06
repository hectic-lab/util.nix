{
  description = "yukkop's nix utilities";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };
  };

  outputs = { self, nixpkgs, rust-overlay }:
  let
    lib = nixpkgs.lib;
    recursiveUpdate = lib.recursiveUpdate;

    supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" ];

    forSpecSystemsWithPkgs = supportedSystems: pkgOverlays: f:
      builtins.foldl' (acc: system:
        let
          pkgs = import nixpkgs { 
            inherit system;
            overlays = pkgOverlays;
          };
          systemOutputs = f { system = system; pkgs = pkgs; };
        in
          recursiveUpdate acc systemOutputs
      ) {} supportedSystems;

    forAllSystemsWithPkgs = pkgOverlays: f: forSpecSystemsWithPkgs supportedSystems pkgOverlays f;

    envErrorMessage = varName: "Error: The ${varName} environment variable is not set.";

    parseEnv = import ./parse-env.nix;

    dotEnv = builtins.getEnv "DOTENV";
    minorEnvironment = 
    if dotEnv != "" then 
      if builtins.pathExists dotEnv then
        parseEnv dotEnv
      else
        throw "${dotEnv} file not exist"
    else 
      if builtins.pathExists ./.env then
        parseEnv ./.env
      else
        {};

  in
  forAllSystemsWithPkgs [ (import rust-overlay) ] ({ system, pkgs }:
  {
    packages.${system} = 
    let
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
    in
    {
      nvim-alias = pkgs.callPackage ./package/nvim-alias.nix {};
      nvim-pager = pkgs.callPackage ./package/nvim-pager.nix {};
      printobstacle = pkgs.callPackage ./package/printobstacle.nix {};
      printprogress = pkgs.callPackage ./package/printprogress.nix {};
      colorize = pkgs.callPackage ./package/colorize.nix {};
      github.gh-tl = pkgs.callPackage ./package/github/gh-tl.nix {};
      supabase-with-env-collection = pkgs.callPackage ./package/supabase-with-env-collection.nix {};
      migration-name = pkgs.callPackage ./package/migration-name.nix {};
      prettify-log = pkgs.callPackage ./package/prettify-log/default.nix rust.commonArgs;
      pg = {
        pg-from = pkgs.callPackage ./package/postgres/pg-from/default.nix rust.commonArgs;
        pg-migration = pkgs.callPackage ./package/postgres/pg-migration/default.nix rust.commonArgs;
      };
    };

    devShells.${system} = 
    let
      shells = self.devShells.${system};
    in
    {
      default = pkgs.mkShell {
        buildInputs = (with self.packages.${system}; [
          nvim-alias
	  #prettify-log
	  nvim-pager
        ]) ++ (with pkgs; [
	  git
	  jq
	  yq-go
	  curl
	]);

        # environment
        PAGER="${self.packages.${system}.nvim-pager}/bin/pager";
      };
      rust =
      let
        rustToolchain = if builtins.pathExists ./rust-toolchain.toml then
          pkgs.pkgsBuildHost.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml
        else
	  pkgs.pkgsBuildHost.rust-bin.stable."1.81.0".default;
      in
      shells.default //
      (pkgs.mkShell {
        nativeBuildInputs = [ 
	   rustToolchain
	   pkgs.pkg-config
	];
      });
      haskell = shells.default // (pkgs.mkShell {
        buildInputs = [ pkgs.stack ];
      });
    };


    nixosModules.${system} = {
      "preset.default" = { pkgs, modulesPath, ... }: {
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
              { from = "host"; host.port = 40500; guest.port = 22; }
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
            allowedTCPPorts = [ ];
          };

	  environment = {
	    defaultPackages = [];
            systemPackages = (with pkgs; [ 
              curl
              neovim
	      yq-go
	      jq
	      htop-vim
            ]) ++ (with self.packages.${system}; [
	      prettify-log
	      nvim-pager
            ]);
	    variables = {
              PAGER=with self.packages.${system}; "${nvim-pager}/bin/pager";
	    };
	  };

	  
          system.stateVersion = "24.11";
      };
      "hardware.hetzner" = { ... }: {
          boot.loader.grub.device = "/dev/sda";
          boot.initrd.availableKernelModules = [
            "ata_piix"
            "uhci_hcd"
            "xen_blkfront"
            "vmw_pvscsi"
          ];
          boot.initrd.kernelModules = [ "nvme" ];
          fileSystems."/" = { device = "/dev/sda1"; fsType = "ext4"; };
      };
    };
  }) // {
    overlays.default =
    final: prev: (
    let
      version = "1.6.1";
      buildHttpExt = versionSuffix: let
          buildPostgresqlExtension =
            prev.callPackage (import (builtins.path {
              name = "extension-builder";
              path = ./buildPostgresqlExtension.nix;
            })) {
              postgresql = prev."postgresql_${versionSuffix}";
            };
        in buildPostgresqlExtension {
          pname = "http";
	  inherit version;
          src = prev.fetchFromGitHub {
            owner = "pramsey";
            repo = "pgsql-http";
            rev  = "v${version}";
            hash = "sha256-C8eqi0q1dnshUAZjIsZFwa5FTYc7vmATF3vv2CReWPM=";
          };
          nativeBuildInputs = with prev; [ pkg-config curl ];
        };
    in
    {
      hectic = self.packages.${prev.system};
      postgresql_17 = prev.postgresql_17 // { pkgs = prev.postgresql_17.pkgs // { http = buildHttpExt "17"; }; };
      postgresql_16 = prev.postgresql_16 // { pkgs = prev.postgresql_16.pkgs // { http = buildHttpExt "16"; }; };
      postgresql_15 = prev.postgresql_15 // { pkgs = prev.postgresql_15.pkgs // { http = buildHttpExt "15"; }; };
      postgresql_14 = prev.postgresql_14 // { pkgs = prev.postgresql_14.pkgs // { http = buildHttpExt "14"; }; };
    });
    lib = {
      # -- For all systems --
      inherit dotEnv minorEnvironment parseEnv forAllSystemsWithPkgs forSpecSystemsWithPkgs;

      makeEnvironment = envVars:
        builtins.listToAttrs
          (map (name: { inherit name; value = self.lib.getEnv name; }) envVars);

      # -- Env processing --
      getEnv = varName: let 
        var = builtins.getEnv varName;
      in 
      if var != "" then
        var
      else if minorEnvironment ? varName then
        minorEnvironment."${varName}"
      else
        throw (envErrorMessage varName);

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
