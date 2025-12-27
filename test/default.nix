{ system, inputs, self, pkgs, flake }: 
let
  # Import existing test checks
  testChecks = import ./package { inherit system inputs self pkgs; };
  
  # Get all packages from the packages output
  allPackages = import ../package { inherit flake self inputs pkgs system; };
  
  # Prefix package names with "package-" to distinguish them in checks
  prefixedPackages = pkgs.lib.mapAttrs'
    (name: value: {
      name = "package-${name}";
      inherit value;
    })
    allPackages;
in
  # Merge test checks with all packages
  testChecks // prefixedPackages

