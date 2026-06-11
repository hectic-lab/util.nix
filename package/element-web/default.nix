{
  lib,
  stdenv,
  fetchFromGitHub,
  jq,
  nodejs,
  jitsi-meet,
  fetchPnpmDeps,
  pnpm_10,
  pnpmConfigHook,
  faketty,
  config,
  conf ? config.element-web.conf or { },
}:

let
  pnpm = pnpm_10;
  patchDir = ./patches;
  patches = if builtins.pathExists patchDir then map (name: patchDir + "/${name}") (
    builtins.filter (name: lib.hasSuffix ".patch" name) (builtins.attrNames (builtins.readDir patchDir))
  ) else [ ];
  noPhoningHome = {
    disable_guests = true;
  };
  jitsi-meet-override = jitsi-meet.overrideAttrs (previousAttrs: {
    meta = removeAttrs previousAttrs.meta [ "knownVulnerabilities" ];
  });
  element-web-unwrapped = stdenv.mkDerivation (finalAttrs: {
    pname = "element-web";
    version = "1.12.20";

    src = fetchFromGitHub {
      owner = "element-hq";
      repo = "element-web";
      tag = "v${finalAttrs.version}";
      hash = "sha256-pbzuPgKJ0DmrDSTO7ZTDArX+Xr9k/ndAGZvQg2kMTMQ=";
    };

    #inherit patches; #WIP

    pnpmDeps = fetchPnpmDeps {
      pname = "element";
      inherit (finalAttrs) version src;
      inherit pnpm;
      fetcherVersion = 3;
      hash = "sha256-snm7vaHCVX6vYrkmsz5HlYMKx5Ks3K9jvUinkJ41CU0=";
    };

    nativeBuildInputs = [
      jq
      nodejs
      pnpm
      pnpmConfigHook
      faketty
    ];

    buildPhase = ''
      runHook preBuild

      cd apps/web

      export VERSION=${finalAttrs.version}
      faketty pnpm run build

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      cp -R webapp $out
      cp ${jitsi-meet-override}/libs/external_api.min.js $out/jitsi_external_api.min.js
      echo "${finalAttrs.version}" > "$out/version"
      jq -s '.[0] * $conf' "config.sample.json" --argjson "conf" '${builtins.toJSON noPhoningHome}' > "$out/config.json"

      runHook postInstall
    '';

    meta = {
      description = "Glossy Matrix collaboration client for the web";
      homepage = "https://element.io/";
      changelog = "https://github.com/element-hq/element-web/blob/v${finalAttrs.version}/CHANGELOG.md";
      teams = [ lib.teams.matrix ];
      license = lib.licenses.agpl3Plus;
      platforms = lib.platforms.all;
    };
  });
in
if conf == { } then
  element-web-unwrapped
else
  stdenv.mkDerivation {
    pname = "${element-web-unwrapped.pname}-wrapped";
    inherit (element-web-unwrapped) version meta;

    dontUnpack = true;

    nativeBuildInputs = [ jq ];

    installPhase = ''
      runHook preInstall

      mkdir -p $out
      ln -s ${element-web-unwrapped}/* $out
      rm $out/config.json
      jq -s '.[0] * $conf' "${element-web-unwrapped}/config.json" --argjson "conf" ${lib.escapeShellArg (builtins.toJSON conf)} > "$out/config.json"

      runHook postInstall
    '';

    passthru = {
      inherit conf;
    };
  }
