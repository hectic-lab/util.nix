{ callPackage }: rec {
  writeShellApplication = callPackage ./writeShellApplication.nix  {};
  writeDash             = callPackage ./writeDash.nix              {};
  writeC                = callPackage ./writeC.nix                 {};
  writeCBin             = name: writeC "/bin/${name}";
  writeMinCBin          = name: includes: body: writeMinC "/bin/${name}" includes body;
  writeMinC             = name: includes: body:
        writeC name ''
          ${builtins.concatStringsSep "\n" (map (h: "#include " + h) includes)}

          int main(int argc, char *argv[]) {
              ${body}
          }
        '';
}
