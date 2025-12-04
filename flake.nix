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
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
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
    packages.${system}         = import ./package           { inherit flake self inputs pkgs system; };
    devShells.${system}        = import ./devshell          { inherit flake self inputs pkgs system; };
    legacyPackages.${system}   = import ./legacy            { inherit flake self inputs pkgs system; };
    nixosConfigurations        =                            {
      "xray|${system}"         = import ./nixos/system/xray { inherit flake self inputs system; };
    };
    checks.${system}           = import ./test              { inherit flake self inputs pkgs system; };
  }) // {
    lib = self-lib;
    overlays.default           = import ./overlay           { inherit flake self inputs; };
    nixosModules               = import ./nixos/module      { inherit flake self inputs; };
    templates                  = import ./template          { inherit flake self inputs; };
  };
}
