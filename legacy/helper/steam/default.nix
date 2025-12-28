{ stdenv, steamcmd }: {
  buildSteamServer = steamId: stdenv.mkDerivation {
    pname = "astroneer-dedicated-server";
    version = "latest";
  
    src = null;
  
    nativeBuildInputs = [
      steamcmd
    ];
  
    buildPhase = ''
      export HOME=$TMPDIR
      mkdir -p $out
      steamcmd \
        +force_install_dir $out \
        +login anonymous \
        +app_update ${steamId} validate \
        +quit
    '';
  
    installPhase = "true";
  
    dontFixup = true;
    dontStrip = true;
  };
}
