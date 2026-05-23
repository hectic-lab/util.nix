{ pkgs }:

pkgs.stdenv.mkDerivation {
  pname = "media-browser";
  version = "0.1.0";
  src = ./.;
  nativeBuildInputs = [ pkgs.makeWrapper ];
  installPhase = ''
    mkdir -p $out/bin
    cp $src/app.py $out/bin/media-browser
    chmod +x $out/bin/media-browser
    makeWrapper ${pkgs.python3.withPackages (ps: [
      ps.flask
      ps.psycopg2
      ps.boto3
      ps.pyyaml
    ])}/bin/python3 $out/bin/media-browser-wrapped \
      --add-flags $out/bin/media-browser
  '';
}
