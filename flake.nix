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
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs-25-05";
    };
    hyprland = {
      url = "github:hyprwm/Hyprland";
      inputs.nixpkgs.follows = "nixpkgs-25-05";
    };
    nixvim = {
      url = "github:nix-community/nixvim/nixos-25.05";
      inputs.nixpkgs.follows = "nixpkgs-25-05";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs-25-05";
    };
    impermanence = {
      url = "github:nix-community/impermanence";
      inputs.nixpkgs.follows = "nixpkgs-25-05";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs-25-05";
    };
  };

  outputs = {
    self,
    nixpkgs-25-05,
    rust-overlay,
    ...
  }@inputs: let
    flake    = ./.;
    nixpkgs  = nixpkgs-25-05;
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
    packages.${system}         = import ./package      { inherit system self pkgs; };
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
  }) // {
    lib = self-lib;
    overlays.default           = import ./overlay      { inherit flake self inputs nixpkgs; };
    nixosModules               = import ./nixos/module { inherit flake self inputs nixpkgs; };
    templates                  = import ./template     { inherit flake self inputs nixpkgs; };
  };
}
