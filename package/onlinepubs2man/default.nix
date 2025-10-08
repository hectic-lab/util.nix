{ symlinkJoin, writeShellApplication, pandoc, gzip, man-db }:
let
  build-man = writeShellApplication {
    name = "build-man";
    runtimeInputs = [ pandoc gzip man-db ];
    text = builtins.readFile ./build-man.sh;
  };

  download-html = writeShellApplication {
    name = "download-html";
    runtimeInputs = [ ];
    text = builtins.readFile ./download-html.sh;
  };
in
symlinkJoin {
  name = "onlinepubs2man";
  paths = [ download-html build-man ];
}
