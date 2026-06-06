{ pkgs, ... }: let
  elementWeb = pkgs.hectic.element-web;
  elementWebVideoMessages = pkgs.hectic.element-web.override {
    conf = {
      hectic.videoMessages.enabled = true;
    };
  };
  playwrightHarness = ./playwright;
in {
  element-web-video-recorder = pkgs.runCommand "element-web-video-recorder"
  {
    nativeBuildInputs = [
      pkgs.jq
      pkgs.nodejs
      pkgs.playwright-driver
    ];
  } ''
    set -eu

    test -d ${elementWeb}
    test -f ${elementWeb}/config.json
    jq -e '.disable_guests == true' ${elementWeb}/config.json

    test -d ${elementWebVideoMessages}
    test -f ${elementWebVideoMessages}/config.json
    jq -e '.disable_guests == true' ${elementWebVideoMessages}/config.json
    jq -e '.hectic.videoMessages.enabled == true' ${elementWebVideoMessages}/config.json

    mkdir -p "$out"
    echo "element-web-video-recorder: starting Playwright harness"
    export HOME="$TMPDIR/home"
    export NODE_PATH=${pkgs.playwright-driver}
    export PLAYWRIGHT_CORE_PATH=${pkgs.playwright-driver}
    export PLAYWRIGHT_BROWSERS_PATH=${pkgs.playwright-driver.browsers}
    export VIDEO_RECORDER_ACTION_TIMEOUT_MS=5000
    export VIDEO_RECORDER_LAUNCH_TIMEOUT_MS=15000
    export VIDEO_RECORDER_TOTAL_TIMEOUT_MS=60000
    mkdir -p "$HOME"
    timeout 75s node ${playwrightHarness}/run-video-recorder-harness.js "$out/playwright"
    echo "element-web-video-recorder: Playwright harness completed"
  '';
}
