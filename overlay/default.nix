{ inputs, self, nixpkgs, ... }: let
  lib = nixpkgs.lib;
in final: prev: (
  let
    hectic-packages = self.packages.${prev.system};
  in {
    hectic = hectic-packages;
    postgresql_17 = prev.postgresql_17 // {pkgs = prev.postgresql_17.pkgs // {
      http = hectic-packages.pg-17-ext-http;
      pg_smtp_client = hectic-packages.pg-17-ext-smtp-client;
      plhaskell = hectic-packages.pg-17-ext-plhaskell;
      plsh = hectic-packages.pg-17-ext-plsh;
      hemar = hectic-packages.pg-17-ext-hemar;
    };};
    postgresql_16 = prev.postgresql_16 // {pkgs = prev.postgresql_16.pkgs // {
      http = hectic-packages.pg-16-ext-http;
      pg_smtp_client = hectic-packages.pg-16-ext-smtp-client;
      plhaskell = hectic-packages.pg-16-ext-plhaskell;
      plsh = hectic-packages.pg-16-ext-plsh;
      hemar = hectic-packages.pg-16-ext-hemar;
    };};
    postgresql_15 = prev.postgresql_15 // {pkgs = prev.postgresql_15.pkgs // {
      http = hectic-packages.pg-15-ext-http;
      pg_smtp_client = hectic-packages.pg-15-ext-smtp-client;
      plhaskell = hectic-packages.pg-15-ext-plhaskell;
      plsh = hectic-packages.pg-15-ext-plsh;
      hemar = hectic-packages.pg-15-ext-hemar;
    };};
    writers = let
      writeC = name: argsOrScript:
        if lib.isAttrs argsOrScript && !lib.isDerivation argsOrScript
        then
          prev.writers.makeBinWriter (
            argsOrScript
            // {
              compileScript = ''
                # Force gcc to treat the input file as C code
                ${prev.gcc}/bin/gcc -fsyntax-only -xc $contentPath
                if [ $? -ne 0 ]; then
                  echo "Syntax check failed"
                  exit 1
                fi
                ${prev.gcc}/bin/gcc -xc -o $out $contentPath
              '';
            }
          )
          name
        else
          prev.writers.makeBinWriter {
            compileScript = ''
              # Force gcc to treat the input file as C code
              ${prev.gcc}/bin/gcc -fsyntax-only -xc $contentPath
              if [ $? -ne 0 ]; then
                echo "Syntax check failed"
                exit 1
              fi
              ${prev.gcc}/bin/gcc -xc -o $out $contentPath
            '';
          }
          name
          argsOrScript;
      writeMinC = name: includes: body:
        writeC name ''
          ${builtins.concatStringsSep "\n" (map (h: "#include " + h) includes)}

          int main(int argc, char *argv[]) {
              ${body}
          }
        '';
    in
      prev.writers
      // {
        writeCBin = name: writeC "/bin/${name}";
        writeC = writeC;
        writeMinCBin = name: includes: body: writeMinC "/bin/${name}" includes body;
        writeMinC = writeMinC;
      };
  }
)
