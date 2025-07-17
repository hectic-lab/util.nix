{
  inputs,
  flake,
  self
}: {
  modulesPath,
  pkgs,
  lib,
  ...
}: {
  imports = [
    self.nixosModules.hectic
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  hectic = {
    archetype.dev.enable = true;
    hardware.hetzner-cloud.enable = true;
  };

  users.users.root.openssh.authorizedKeys.keys = [
    ''ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICrbBG+U07f7OKvOxYIGYCaNvyozzxQF+I9Fb5TYZErK yukkop vm-postgres''
  ];



  services.postgresql =
  let
    package = pkgs.postgresql_15;
  in {
    enable = true;
    package = package;
    settings = 
    {
      port = 64317;
      listen_addresses = lib.mkForce "*";
      shared_preload_libraries = "";
    };
    extensions = [ package.pkgs.hemar ];
    authentication =  builtins.concatStringsSep "\n" [
      "local all       all     trust"
      "host  sameuser    all     127.0.0.1/32 scram-sha-256"
      "host  sameuser    all     ::1/128 scram-sha-256"
    ];
    initialScript = pkgs.writeText "init-sql-script" ''
      SET log_min_messages TO DEBUG1;
      SET client_min_messages TO DEBUG1;
      ALTER DATABASE postgres SET log_min_messages TO DEBUG1;
      ALTER DATABASE postgres SET client_min_messages TO DEBUG1;
      CREATE EXTENSION "hemar";

      \i ${flake}/package/c/hemar/test/mod.sql
    '';
  };                   

  environment.systemPackages =  with pkgs; [
    gdb
    hectic.nvim-pager
    (writeScriptBin "check" ''
      journalctl -u postgresql.service | grep postgresql-post-start | sed 's|psql:/nix/store/[^:]*:[0-9]*: ||' | sed 's|^[^:]*:[^:]*:[^:]*: ||' | grep -v '^\[.*\]' | ${hectic.prettify-log}/bin/prettify-log --color-output
    '')
  ];
  programs.zsh.shellAliases = self.lib.sharedShellAliasesForDevVm // {
    conn = "sudo su postgres -c 'psql -p 64317'";
  };

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
