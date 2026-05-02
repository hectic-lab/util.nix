{ pkgs, writeTextFile, lib, linux-devshell-standalone }:
let
  psScriptTemplate = builtins.readFile ./windows-devshell.ps1;

  # Get the linux-devshell standalone script content and base64 encode it
  linuxDevShellBase64 = lib.removeSuffix "\n"
    (builtins.readFile
      (pkgs.runCommand "base64-linux-devshell" {}
        ''
          ${pkgs.coreutils}/bin/base64 -w 0 ${linux-devshell-standalone} > $out
        ''));

  # Standalone PowerShell script (single file for Windows)
  windowsDevShellStandalone = writeTextFile {
    name = "windows-devshell.ps1";
    executable = false;
    text = lib.replaceStrings ["@LINUX_DEVSHELL_BASE64@"] [linuxDevShellBase64] psScriptTemplate;
    meta = {
      description = "Standalone windows-devshell PowerShell script (single file)";
    };
  };

in
{
  windows-devshell-standalone = windowsDevShellStandalone;
}
