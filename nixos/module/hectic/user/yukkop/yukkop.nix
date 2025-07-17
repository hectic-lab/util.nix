{
  self,
  inputs,
  ...
}:
{
  config,
  pkgs,
  lib,
  ...
}: let 
  name = builtins.baseNameOf ./.;
  home = "/home/${name}";
  cfg = config.hectic.user.yukkop;
in {
  options.hectic.user.yukkop.enable = lib.mkEnableOption "Enable user.yukkop";

  config = lib.mkIf cfg.enable {
    home = {
      username = name;
      homeDirectory = home;
      packages = [];
      stateVersion = "25.05";
    };

    xdg = {
      enable = true;
      userDirs = {
        enable = true;
        pictures    = "${home}/px";
        videos      = "${home}/vd";
        music       = "${home}/mu";
        documents   = "${home}/dc";
        downloads   = "${home}/dw";
        desktop     = "${home}/dx";
        publicShare = "${home}/pu";
        templates   = "${config.xdg.dataHome}/templates";
      };
      mimeApps = {
        enable = true;
        defaultApplications = {

          # Files
          "application/x-shellscript" = [ "nvim.desktop" ];
          "text/x-shellscript" = [ "nvim.desktop" ];
          "text/plain" = [ "nvim.desktop" ];
          "inode/directory" = [ "pcmanfm.desktop" ];

          # Images
          "image/png" = [ "sxiv.desktop" ];
          "image/jpeg" = [ "sxiv.desktop" ];
          "image/gif" = [ "sxiv.desktop" ];
          "image/webp" = [ "sxiv.desktop" ];
          "image/x-xcf" = [ "gimp.desktop" ];

          # Videos
          "video/x-matroska" = [ "mpv.desktop" ];

          # # Application-specific
          # "application/postscript" = [ "pdf.desktop" ];
          # "application/pdf" = [ "pdf.desktop" ];
          # "application/rss+xml" = [ "rss.desktop" ];
          # "application/x-bittorrent" = [ "torrent.desktop" ];

          # Protocols
          "x-scheme-handler/http"  = [ "firefox.desktop" ];
          "x-scheme-handler/https" = [ "firefox.desktop" ];
          # "x-scheme-handler/magnet" = [ "torrent.desktop" ];
          # "x-scheme-handler/mailto" = [ "mail.desktop" ];
          # "x-scheme-handler/lbry" = [ "lbry.desktop" ];
          # "x-scheme-handler/tg" = [ "telegram.desktop" ];

          # text/x-shellscript=text.desktop;
          # x-scheme-handler/magnet=torrent.desktop;
          # application/x-bittorrent=torrent.desktop;
          # x-scheme-handler/mailto=mail.desktop;
          # text/plain=text.desktop;
          # application/postscript=pdf.desktop;
          # application/pdf=pdf.desktop;
          # image/png=img.desktop;
          # image/jpeg=img.desktop;
          # image/gif=img.desktop;
          # image/webp=img.desktop;
          # application/rss+xml=rss.desktop;
          # video/x-matroska=video.desktop;
          # x-scheme-handler/lbry=lbry.desktop;
          # inode/directory=file.desktop;
          # text/html=chromium.desktop;
          # x-scheme-handler/http=chromium.desktop;
          # x-scheme-handler/https=chromium.desktop;
          # x-scheme-handler/about=chromium.desktop;
          # x-scheme-handler/unknown=chromium.desktop;
        };
      };
    };
  };
}
