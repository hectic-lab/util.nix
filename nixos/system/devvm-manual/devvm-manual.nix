{
  inputs,
  flake,
  self,
}: {
  lib,
  pkgs,
  modulesPath,
  config,
  ...
}:
{
  imports = [
    self.nixosModules.hectic
    (modulesPath + "/profiles/qemu-guest.nix")
  ];
 
  hectic = {
    archetype.dev.enable = true;
    hardware.hetzner-cloud.enable = true;
  };
 
  environment.systemPackages = with pkgs.writers; [
    (writeMinCBin "minc-hello-world" ["<stdio.h>"] /*c*/ ''
      printf("hello world\n");
    '')
    (writeMinCBin "minc-env" ["<stdio.h>" "<stdlib.h>"] /*c*/ ''
      char *env_name;
      if (argc > 1) {
        env_name = argv[1];
      } else {
        env_name = "HOME";
      }
      char *value = getenv(env_name);
      if (value) {
          printf("%s: %s\n", env_name, value);
      } else {
          printf("Environment variable %s not found.\n", env_name);
      }
    '')
    (writeMinCBin "minc-env-check" ["<stdio.h>" "<stdlib.h>"] /*c*/ ''
      char *env_name;
      if (argc > 1) {
        env_name = argv[1];
      } else {
        env_name = "HOME";
      }
 
      char *value = getenv(env_name);
      if (value) {
          char buffer[128];
          sprintf(buffer, "echo $%s\n", env_name);
          system(buffer);
      } else {
          printf("Environment variable %s not found.\n", env_name);
      }
    '')
  ];
 
  users.users.root.openssh.authorizedKeys.keys = [
    ''ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICrbBG+U07f7OKvOxYIGYCaNvyozzxQF+I9Fb5TYZErK yukkop vm-postgres''
  ];
 
  programs.zsh.shellAliases = self.lib.sharedShellAliasesForDevVm;
 
  virtualisation = {
    vmVariant = {
      systemd.services.fix-root-perms = {
        description = "Fix root directory permissions";
        after = [ "local-fs.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.coreutils}/bin/chmod 755 /";
        };
      };
      virtualisation = {
        diskSize = 1024*6;
        diskImage = null;
        forwardPorts = [ ];
      };
    };
  };
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      80
    ];
  };
}
