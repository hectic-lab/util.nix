{ flake, inputs, self, nixpkgs }: let
  lib = nixpkgs.lib;
  recursiveUpdate = nixpkgs.lib.recursiveUpdate;

  envErrorMessage = varName: "Error: The ${varName} environment variable is not set.";

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

  forAllSystemsWithPkgs = pkgOverlays: f: forSystemsWithPkgs commonSystems pkgOverlays f;

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
  inherit dotEnv minorEnvironment parseEnv forAllSystemsWithPkgs forSystemsWithPkgs commonSystems;

  forSystems = systems: nixpkgs.lib.genAttrs systems;
  forAllSystems = nixpkgs.lib.genAttrs commonSystems;

  shellModules.logs = ''
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    PURPLE='\033[0;35m'
    MAGENTA="$PURPLE"
    CYAN='\033[0;36m'
    WHITE='\033[1;37m'
    NC='\033[0m' # No Color

    LOG_PATH="/var/log/hectic/activation.log"

    mkdir -p "$(dirname "$LOG_PATH")"

    log_info()    { text=$1; shift; printf "%b ''${text}%b\n" "$BLUE"   "$@" "$NC" | tee -a "$LOG_PATH" >&2; }
    log_success() { text=$1; shift; printf "%b ''${text}%b\n" "$GREEN"  "$@" "$NC" | tee -a "$LOG_PATH" >&2; }
    log_warning() { text=$1; shift; printf "%b ''${text}%b\n" "$YELLOW" "$@" "$NC" | tee -a "$LOG_PATH" >&2; }
    log_error()   { text=$1; shift; printf "%b ''${text}%b\n" "$RED"    "$@" "$NC" | tee -a "$LOG_PATH" >&2; }
    log_step()    { text=$1; shift; printf "%b ''${text}%b\n" "$PURPLE" "$@" "$NC" | tee -a "$LOG_PATH" >&2; }

    log_header() { printf "\n%b=== %s ===%b\n" "$WHITE" "$@" "$NC" | tee -a "$LOG_PATH" >&2; }
  '';

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
