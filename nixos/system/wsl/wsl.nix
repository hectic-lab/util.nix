{
  inputs,
  flake,
  self,
}: {
  lib,
  pkgs,
  config,
  ...
}: {
  imports = [
    self.nixosModules.hectic
  ];

  hectic = {
    archetype.base.enable = true;
    program.zsh.enable    = true;
    program.nixvim.enable = true;
    user.yukkop.enable    = true;
  };

  wsl.defaultUser = "yukkop";

  # 16 GiB swap
  swapDevices = [{
    device = "/var/lib/swapfile";
    size   = 16 * 1024;
  }];

  users.groups.owner = {};

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      UseDns                 = true;
      X11Forwarding          = false;
      PermitRootLogin        = "no";
    };
  };

  virtualisation.docker.enable = true;

  hardware.opengl.enable = true;

  console.keyMap = "us";

  environment.systemPackages = with pkgs; [
    ripgrep
    man-pages
    man-pages-posix
    man-db
    ffmpeg
  ];

  documentation.dev.enable         = true;
  documentation.man.man-db.enable  = false;
  documentation.man.mandoc.enable  = true;

  services.samba = {
    enable = true;
    shares.sshfs = {
      path        = "/home/yukkop/umbriel/vproxy";
      browseable  = true;
      "read only" = false;
      "guest ok"  = true;
    };
  };

  networking.firewall.allowedTCPPorts = [ 139 445 ];
  networking.firewall.allowedUDPPorts = [ 137 138 ];

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
  ];

  environment.variables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };

  # WSL-local shell aliases
  programs.bash.shellAliases = {
    nrs = "sudo nixos-rebuild switch --flake /home/yukkop/pj/util.nix#wsl";
  };

  # WSL: keep imperative stateVersion in the system module
  system.stateVersion = "25.05";
}
