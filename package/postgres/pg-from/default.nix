{
  cargoToml,
  nativeBuildInputs,
  pkgs,
  ...
}: let
  src = ./.;
  cargo = cargoToml src;
in
  pkgs.rustPlatform.buildRustPackage {
    pname = cargo.package.name;
    version = cargo.package.version;

    inherit nativeBuildInputs src;

    cargoLock.lockFile = ./Cargo.lock;

    doCheck = true;
  }
