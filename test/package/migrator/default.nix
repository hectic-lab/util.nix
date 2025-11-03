{ inputs, self, pkgs, system, ... }: let 
  lib = inputs.nixpkgs.lib;

  # turn anything under ./test into a derivation that exposes $out/run.sh
  mkTestDrv = name: type:
    if type == "directory" then
      pkgs.runCommand "test-${name}" {} ''
        if ! [ -f ${./test + "/${name}" + /run.sh} ]; then
          echo no run.sh in test/${name}
	  exit 1
        fi

        mkdir -p "$out"
        cp -r ${./test + "/${name}"}/* "$out/"
        chmod +x "$out/run.sh"
      ''
    else if lib.hasSuffix ".sh" name then
      pkgs.runCommand "test-${lib.removeSuffix ".sh" name}" {} ''
        mkdir -p "$out"
        install -Dm755 ${./test + "/${name}"} "$out/run.sh"
      ''
    else
      null;

  testDir = builtins.readDir ./test;

  # attrset: testName -> drv with run.sh
  testDrvs =
    lib.mapAttrs' (n: v:
      lib.nameValuePair (lib.removeSuffix ".sh" n) v
    ) (lib.filterAttrs (_: v: v != null)
      (lib.mapAttrs (n: t: mkTestDrv n t) testDir));

  migrator = self.packages.${system}.migrator;
  mkPgTest = testName: testDrv: pkgs.runCommand "migrator-test-${testName}"
  {
    nativeBuildInputs = [ pkgs.coreutils pkgs.gnugrep pkgs.gnused ];
    buildInputs = [ migrator pkgs.postgresql ];
  } ''
    ${builtins.readFile self.legacyPackages.${system}.helpers.posix-shell.log}
    test=${testDrv}
    ${builtins.readFile ./lauch.sh}
  '';
in builtins.trace testDir (lib.mapAttrs (name: drv: mkPgTest name drv) testDrvs)
