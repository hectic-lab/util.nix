{ inputs, self, nixpkgs, ... }: let
  lib = nixpkgs.lib;
in final: prev: (
  let
    packages = self.packages.${prev.system};
    legacyPackages = self.legacyPackages.${prev.system};
  in {
    hectic = packages;
    postgresql_17 = prev.postgresql_17 // {pkgs = prev.postgresql_17.pkgs // {
      http = packages.pg-17-ext-http;
      pg_smtp_client = packages.pg-17-ext-smtp-client;
      plhaskell = packages.pg-17-ext-plhaskell;
      plsh = packages.pg-17-ext-plsh;
      hemar = packages.pg-17-ext-hemar;
    };};
    postgresql_16 = prev.postgresql_16 // {pkgs = prev.postgresql_16.pkgs // {
      http = packages.pg-16-ext-http;
      pg_smtp_client = packages.pg-16-ext-smtp-client;
      plhaskell = packages.pg-16-ext-plhaskell;
      plsh = packages.pg-16-ext-plsh;
      hemar = packages.pg-16-ext-hemar;
    };};
    postgresql_15 = prev.postgresql_15 // {pkgs = prev.postgresql_15.pkgs // {
      http = packages.pg-15-ext-http;
      pg_smtp_client = packages.pg-15-ext-smtp-client;
      plhaskell = packages.pg-15-ext-plhaskell;
      plsh = packages.pg-15-ext-plsh;
      hemar = packages.pg-15-ext-hemar;
    };};
    writers = prev.writers // legacyPackages.writers;
  }
)
