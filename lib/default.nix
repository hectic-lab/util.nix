{ flake, inputs, self }: let
  nixpkgs = inputs.nixpkgs-25-05;
  lib = nixpkgs.lib;
  recursiveUpdate = nixpkgs.lib.recursiveUpdate;

  envErrorMessage = varName: "Error: The ${varName} environment variable is not set.";

  AllSystems = [
    "aarch64-darwin"
    "aarch64-linux"    
    "armv5tel-linux"     
    "armv6l-linux"    
    "armv7l-linux"      
    "i686-linux"
    "mipsel-linux"
    "powerpc64le-linux"
    "riscv64-linux"
    "x86_64-darwin"
    "x86_64-linux"
  ];

  commonSystems = [
    "x86_64-linux"
    "aarch64-linux"
    "x86_64-darwin"
    "aarch64-darwin"
  ];

  forSystemsWithPkgs = supportedSystems: pkgOverlays: f:
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

  forAllSystemsWithPkgs = pkgOverlays: f: forSystemsWithPkgs AllSystems pkgOverlays f;

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
in {
  # -- For all systems --
  inherit dotEnv minorEnvironment parseEnv forAllSystemsWithPkgs forSystemsWithPkgs commonSystems AllSystems;

  forSystems = systems: nixpkgs.lib.genAttrs systems;
  forAllSystems = nixpkgs.lib.genAttrs AllSystems;

  shellModules = {
    logs = builtins.readFile ./shell/logs.sh;
    check-tool = builtins.readFile ./shell/check-tool.sh;
    local-dir = builtins.readFile ./shell/local-dir.sh;
  };

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

  readPackages = callPackage: path: extraArgs:
  with lib;
  with builtins;
  pipe path [
    readDir
    (filterAttrs (_: type: type == "directory"))
    (filterAttrs (name: _: pathExists "${path}/${name}/default.nix"))
    (mapAttrs (name: _: callPackage "${path}/${name}" extraArgs))
  ];

  # Like readModulesRecursive, but reads module structure as a one-level keys,
  # so that it is suited for `nix flake show`
  # ```nix
  # {
  #   "foo.bar" = import ./module/foo/bar.nix
  # }
  # ```
  readModulesRecursive' = path: extraArgs:
    with lib;
    with builtins; let
      paths = pipe "${path}" [
        (filesystem.listFilesRecursive)
        (filter (hasSuffix ".nix"))
      ];
      pathToName = flip pipe [
        (removePrefix "${path}/")
        (replaceStrings ["/" ".nix"] ["." ""])
        (removeSuffix ".nix")
      ];
      attrList =
        map (path': {
          name = pathToName (unsafeDiscardStringContext path');
          value = import path' extraArgs;
        })
        paths;
    in
      listToAttrs attrList;

  nixpkgs-lib = nixpkgs.lib;
} // rec {
  /* Supplied a directory, reads it's recursive structure into NixOS modules, so
     that provided a `./module` dir with `module/foo/bar.nix` in it it outputs
     ```nix
     {
       foo.bar = import ./module/foo/bar.nix
     }
    ```
  */
  readModulesRecursive = path:
    lib.mapAttrs' (
      name: value: let
        name' = builtins.replaceStrings [".nix"] [""] name;
      in
        if value == "regular"
        then {
          name = name';
          value = import "${path}/${name}";
        }
        else {
          inherit name;
          value = readModulesRecursive "${path}/${name}";
        }
    ) (builtins.readDir path);
}
