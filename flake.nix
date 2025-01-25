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
      # necessary to load every time .nvimrc
      # makes some magic to shading nvim but still uses nvim that shaded 
      nvim-alias = pkgs.writeShellScriptBin "nvim" ''
        # Source .env file
        if [ -f .env ]; then
            set -a
            . .env
            set +a
        fi

        # Get the directory of this script
        SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
        
        # Remove the script's directory from PATH to avoid recursion
        PATH=$(echo "$PATH" | tr ':' '\n' | grep -v "$SCRIPT_DIR" | paste -sd ':' -)
        
        # Find the system's nvim
        SYSTEM_NVIM=$(command -v nvim)
        
        if [ -z "$SYSTEM_NVIM" ]; then
          echo "Error: nvim not found in PATH" >&2
          exit 1
        fi

        # Execute the system's nvim with your custom arguments
        exec "$SYSTEM_NVIM" --cmd 'lua vim.o.exrc = true' "$@"
      '';
      printobstacle = 
      let
        name = "printobstacle";
      in 
      pkgs.writeShellScriptBin "${name}"  ''
        printf "%s%s%s\n" "''${RED}" "$*" "''${RESET}" 
      '';
      printprogress = 
      let
        name = "printprogress";
      in
      pkgs.writeShellScriptBin "${name}"  ''
        printf "%s%s%s\n" "''${YELLOW}" "$*" "''${RESET}" 
      '';
      colorize = pkgs.writeShellScriptBin "colorize" ''
        awk '
          BEGIN {
            # Define color codes
            RED = "\x1b[31m";
            BLUE = "\x1b[34m";
            GREEN = "\x1b[32m";
            YELLOW = "\x1b[33m";
            MAGENTA = "\x1b[35m";
            CYAN = "\x1b[36m";
            RESET = "\x1b[0m";
          }
          {
            # Apply color based on keywords
            gsub(/ERROR:/, RED "&" RESET, $0);
            gsub(/DEBUG:/, BLUE "&" RESET, $0);
            gsub(/INFO:/, GREEN "&" RESET, $0);
            gsub(/LOG:/, GREEN "&" RESET, $0);
            gsub(/EXCEPTION:/, MAGENTA "&" RESET, $0);
            gsub(/WARNING:/, YELLOW "&" RESET, $0);
            gsub(/NOTICE:/, CYAN "&" RESET, $0);
            gsub(/HINT:/, CYAN "&" RESET, $0);
            gsub(/FATAL:/, MAGENTA "&" RESET, $0);
            gsub(/DETAIL:/, CYAN "&" RESET, $0);
            gsub(/STATEMENT:/, CYAN "&" RESET, $0);
            print;
          }
        '
      '';
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
