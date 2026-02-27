{
  inputs,
  flake,
  self,
  ...
}:
{
  config,
  pkgs,
  lib,
  modulesPath,
  ...
}:
with builtins;
with lib;
let
  domain = "hectic-lab.com";
  sslOpts = {
    sslCertificate    = config.sops.secrets."ssl/porkbun/${domain}/domain.cert.pem".path;
    sslCertificateKey = config.sops.secrets."ssl/porkbun/${domain}/private.key.pem".path;
  };
in {
  imports = [
    self.nixosModules.hectic
    inputs.sops-nix.nixosModules.sops

    self.nixosModules."shadowsocks-rust" # NOTE(nrv): impl
    self.nixosModules."shadowsocks"      # NOTE(nrv): usage/instance

    (import ./containers.nix          { inherit flake self inputs; })
    (import (./. + "/sentinèlla.nix") { inherit flake self inputs domain sslOpts; })
  ];

  hectic = {
    archetype.dev.enable = true;
    hardware.hetzner-cloud = {
      enable                 = true;
      networkMatchConfigName = "enp1s0";
      ipv4                   = "188.245.181.123";
      ipv6                   = "2a01:4f8:c2c:d54a";
    };
  };

  programs.zsh.enable = true;
  programs.zsh.interactiveShellInit = ''
    setopt vi
  '';

  environment.systemPackages = with pkgs; [
    git
    rsync
    python311
    kitty
  ];

  # Secrets config
  sops = {
    gnupg.sshKeyPaths  = [ ];
    age.sshKeyPaths    = [ "/etc/ssh/ssh_host_ed25519_key" ];
    defaultSopsFile    = "${flake}/sus/hectic-lab.yaml";
  };

  users.users.root.openssh.authorizedKeys.keys = [
    # yukkop
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMuP5NSfEQmO6m77xBWZvZ3hk7cw1q2k2vbsFd37rybU u0_a327@localhost"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJBLxMo5icX2Xyng7mcWGnIi+c4ZbVygjPhuU8noCkfZ"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGxgLlX/15Fk7PgIc9FSrA7oRtA8qK4GXfOhj7ZlNUaJ nix-on-droid@localhost"
    # snuff
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFouceNUxI3bGC24/hfA8J3VuBpvTcZh3KhixgrMiLte"
    # nrv
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE/EhBI6sJb2yHbTkqhZiCzUrsLE6t+CZe7RhS22z7w5 nrv@adamantia"
    # github workflow
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKPEUArBxu7NUULT7Pi8ArtVxY1uVbIBSaeRKtqz1sz1"
  ];

  users.users.ds4d = { # NOTE(nrv): artishoque
    isNormalUser = true;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINcjBc57N6MxtMYAHEB/nwZ+OGsG3P1KWO1ZXvzQyhKn ds4d@ds4d"
    ];
  };

  users.users.sshuttle = {
    isNormalUser = true;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKd4iU2E5fiwPwBbeo1ZPo0YBFEj9qBPew/KitaO+OHU"
    ];
  };

  sops.secrets."mailserver/security/hashedPassword" = {};
  sops.secrets."mailserver/yukkop/hashedPassword"   = {};
  sops.secrets."mailserver/snuff/hashedPassword"    = {};
  sops.secrets."mailserver/antoshka/hashedPassword" = {};

  # services.mailserver = {
  #   enable = false;
  #   domain = domain;
  #   loginAccounts = {
  #     "security" = {
  #       hashedPasswordFile = config.sops.secrets."mailserver/security/hashedPassword".path;
  #     };
  #     "yukkop" = {
  #       hashedPasswordFile = config.sops.secrets."mailserver/yukkop/hashedPassword".path;
  #     };
  #     "snuff" = {
  #       hashedPasswordFile = config.sops.secrets."mailserver/snuff/hashedPassword".path;
  #     };
  #     "antoshka" = {
  #       hashedPasswordFile = config.sops.secrets."mailserver/antoshka/hashedPassword".path;
  #     };
  #   };
  # };

  services.redis.servers."vproxy-bot-test-state" = {
    enable = true;
    port   = 6379;
  };

  services.mysql = {
    enable  = true;
    package = pkgs.mariadb;
  };

  networking.firewall = {
    allowedTCPPorts = [
      443
      3306  # mysql
      25565
      55228 # ss-bfs
    ];
    allowedUDPPorts = [
      51820 # wg-bfs
      55228 # ss-bfs
    ];
  };

  virtualisation.docker.enable = true;

  systemd.tmpfiles.rules = [
    "d /var/www/store 0755 nginx nginx -"
  ];

  sops.secrets."ssl/porkbun/${domain}/domain.cert.pem" = { group = "nginx"; mode = "0440"; };
  sops.secrets."ssl/porkbun/${domain}/private.key.pem" = { group = "nginx"; mode = "0440"; };
  sops.secrets."ssl/porkbun/${domain}/public.key.pem"  = { group = "nginx"; mode = "0440"; };

  services.nginx = {
    enable = true;
    virtualHosts.${domain} = sslOpts // {
      forceSSL = true;
      locations."/" = {
        extraConfig = ''
          root ${"${flake}/nixos/system/hectic-lab/static"};
          try_files $uri $uri/ /index.html;
        '';
      };
    };
    virtualHosts."umbriel.${domain}" = sslOpts // {
      forceSSL = true;
      locations."/" = {
        extraConfig = ''
          root ${"${flake}/nixos/system/hectic-lab/static"};
          try_files $uri $uri/ /index.html;
        '';
      };
    };
    virtualHosts."store.${domain}" = sslOpts // {
      forceSSL = true;
      root = "/var/www/store";
      locations."/" = {
        extraConfig = ''
          autoindex on;
        '';
      };
    };
    virtualHosts."snuff.${domain}" = sslOpts // {
      forceSSL = true;
      locations."/" = {
        extraConfig = ''
          proxy_pass     http://188.32.215.29:3993/;
          proxy_redirect off;
        '';
      };
    };
    virtualHosts."nrv.${domain}" = sslOpts // {
      forceSSL = true;
      locations."/" = {
        extraConfig = ''
          proxy_pass     http://127.0.0.1:22842/;
          proxy_redirect off;
        '';
      };
    };
    virtualHosts."yukkop.${domain}" = sslOpts // {
      forceSSL = true;
      locations."/" = {
        extraConfig = ''
          proxy_pass     http://127.0.0.1:9855/;
          proxy_redirect off;
        '';
      };
    };
  };

  # === WireGuard (disabled) ===

  sops.secrets."wg-bfs/private-key" = {};

  # networking.wireguard.interfaces = let
  #   subnet            = "10.13.37";
  #   externalInterface = "eth0";
  # in {
  #   wg-bfs = {
  #     ips        = [ "${subnet}.1/24" ];
  #     listenPort = 51820;
  #     postSetup = ''
  #       ${pkgs.iptables}/bin/iptables -t 'nat' -A 'POSTROUTING' -s '${subnet}.0/24' -o '${externalInterface}' -j 'MASQUERADE'
  #     '';
  #     postShutdown = ''
  #       ${pkgs.iptables}/bin/iptables -t 'nat' -D 'POSTROUTING' -s '${subnet}.0/24' -o '${externalInterface}' -j 'MASQUERADE'
  #     '';
  #     privateKeyFile       = config.sops.secrets."wg-bfs/private-key".path;
  #     generatePrivateKeyFile = false;
  #     peers = with lib; with builtins; let
  #       pubkeys = [
  #         "3dVzf1jxnVVTkLAyxedW+kRQBexZDzYDwpaLIcTrLjc=" # nrv    (host: 2)
  #         "Kk2d0ncj24rO0qbuKh4V4t1OLnmVYbeaYvuEnL2OPFM=" # lysmi  (host: 3)
  #         "BkM/NEDbR/XQ6WYQ0Yt+nJrc2HFCVsoW4QxBmkqxHn8=" # yukkop (host: 4)
  #       ];
  #       hosts  = lists.range 2 254;
  #       zipped = zipLists pubkeys hosts;
  #     in flip map zipped ({ fst, snd }: {
  #       publicKey  = "${fst}";
  #       allowedIPs = [ "${subnet}.${toString snd}/32" ];
  #     });
  #   };
  # };
}
