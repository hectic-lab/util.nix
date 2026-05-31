{
  lib,
  buildGoModule,
  makeWrapper,
  git,
  bash,
  coreutils,
  gzip,
  nodejs,
  openssh,
  fetchPnpmDeps,
  pnpmConfigHook,
  pnpm,
  stdenv,
  sqliteSupport ? true,
  nixosTests,
}:

let
  pname = "gitea";
  version = "1.25.4";
  src = ./source;

  frontend = stdenv.mkDerivation {
    pname = "gitea-frontend";
    inherit src version;

    pnpmDeps = fetchPnpmDeps {
      pname = "gitea-frontend";
      inherit version src;
      fetcherVersion = 2;
      hash = "sha256-0p7P68BvO3hv0utUbnPpHSpGLlV7F9HHmOITvJAb/ww=";
    };

    nativeBuildInputs = [
      nodejs
      pnpmConfigHook
      pnpm
    ];

    buildPhase = ''
      make frontend
    '';

    installPhase = ''
      mkdir -p $out
      cp -R public $out/
    '';
  };
in
buildGoModule rec {
  inherit pname version src;

  proxyVendor = true;
  vendorHash = "sha256-y7HurJg+/V1cn8iKDXepk/ie/iNgiJXsQbDi1dhgark=";

  outputs = [
    "out"
    "data"
  ];

  patches = [ ./static-root-path.patch ];

  overrideModAttrs = _: { postPatch = null; };

  postPatch = ''
    substituteInPlace modules/setting/server.go --subst-var data
  '';

  subPackages = [ "." ];

  nativeBuildInputs = [ makeWrapper ];

  tags = lib.optionals sqliteSupport [
    "sqlite"
    "sqlite_unlock_notify"
  ];

  ldflags = [
    "-s"
    "-w"
    "-X main.Version=${version}"
    "-X 'main.Tags=${lib.concatStringsSep " " tags}'"
  ];

  postInstall = ''
    mkdir $data
    ln -s ${frontend}/public $data/public
    cp -R ./{templates,options} $data
    mkdir -p $out
    cp -R ./options/locale $out/locale

    wrapProgram $out/bin/gitea \
      --prefix PATH : ${
        lib.makeBinPath [
          bash
          coreutils
          git
          gzip
          openssh
        ]
      }
  '';

  passthru = {
    tests = nixosTests.gitea;
  };

  meta = {
    description = "Git with a cup of tea";
    homepage = "https://about.gitea.com";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [
      techknowlogick
      SuperSandro2000
    ];
    mainProgram = "gitea";
  };
}
