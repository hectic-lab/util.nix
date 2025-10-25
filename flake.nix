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
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland = {
      url = "github:hyprwm/Hyprland";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixvim = {
      url = "github:nix-community/nixvim/nixos-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    impermanence = {
      url = "github:nix-community/impermanence";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    rust-overlay,
    ...
  }@inputs: let
    flake    = ./.;
    self-lib = import ./lib { inherit flake self inputs; };
    
    # Create overlay that includes legacy packages
    overlayWithLegacy = system: final: prev: 
      let
        baseOverlay = (import ./overlay { inherit flake self inputs nixpkgs; }) final prev;
        legacyPackages = import ./legacy { inherit system pkgs self; };
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };
      in
        baseOverlay // legacyPackages;
    
    overlays = [ self.overlays.default ];
  in self-lib.forAllSystemsWithPkgs ([(import rust-overlay)] ++ overlays) ({
    system,
    pkgs,
  }: {
    packages.${system}         = import ./package      { inherit system self pkgs inputs; };
    devShells.${system}        = import ./devshell     { inherit system self pkgs; };
    legacyPackages.${system}   = import ./legacy       {
      inherit system self;
      pkgs = import nixpkgs { inherit system; };
    };
    nixosConfigurations = {
      "devvm-manual|${system}" = import ./nixos/system/devvm-manual/default.nix 
        { inherit flake self inputs system; };
      "devvm-hemar|${system}"  = import ./nixos/system/devvm-hemar/default.nix 
        { inherit flake self inputs system; };
    };

    #nixosTests = let
    #  testLib = import (nixpkgs + "/nixos/lib/testing-python.nix") { inherit pkgs; };
    #in {       
    #  "hardware/lenovo-ideapad-15arh7" = testLib.makeTest {
    #    name = "hardware/lenovo-ideapad-15arh7";
    #    nodes.machine = { ... }: {
    #      imports = [ self.nixosModules.hectic ];
    #      services.hardware.lenovo-ideapad-15arh7.enable = true;
    #    };
    #    testScript = ''
    #      start_all()
    #      machine.wait_for_unit("my-service.service")
    #      machine.succeed("journalctl -u my-service -b | grep -qi hello")
    #    '';
    #  };
    #};

    checks = let 
      mkSys = system: opts:
      (nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          self.nixosModules.hectic
          { hectic.hardware.lenovo-ideapad-15arh7 = opts; }
        ];
      });

      cases = {
        #enable          = { enable = true;  };
        #disabled        = { enable = false; };
        #customFoo       = { enable = true; foo = "bar"; };
      };
    in nixpkgs.lib.mapAttrs
        (name: opts: (mkSys system opts).config.system.build.toplevel) cases;
  }) // {
    lib = self-lib;
    overlays.default           = import ./overlay      { inherit flake self inputs nixpkgs; };
    nixosModules               = import ./nixos/module { inherit flake self inputs nixpkgs; };
    templates                  = import ./template     { inherit flake self inputs nixpkgs; };
  };
}
