{
  description = "yukkop's nix utilities";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
  };

  outputs = { self, nixpkgs }:
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
  forAllSystemsWithPkgs [] ({ system, pkgs }:
  {
    packages.${system} = {
      nvim-alias = pkgs.callPackage ./package/nvim-alias.nix {};
      printobstacle = pkgs.callPackage ./package/printobstacle.nix {};
      printprogress = pkgs.callPackage ./package/printprogress.nix {};
      colorize = pkgs.callPackage ./package/colorize.nix {};
      gh_translabeles = pkgs.callPackage ./package/github/gh_translabeles.nix {};
    };

    nixosModules.${system} = {
      "hetzner.hardware" = {
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
    lib = {
      # -- For all systems --
      inherit dotEnv minorEnvironment parseEnv forAllSystemsWithPkgs forSpecSystemsWithPkgs;

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
      cargo = src: (builtins.fromTOML (builtins.readFile "${src}/Cargo.toml"));

      ssh.keys = {
          hetzner-test = {
	      yukkop = ''ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ8scy1tv6zfXX6xyaukhO/fsZwif5rC89DvXNc6XxOf'';
	  };
      };
    };
  };
}
