{ pkgs, ... }: let 
  astroneerServer = pkgs.hectic.helpers.steam.buildSteamServer 728470;
in {
  options = {

  };
  config = {
    systemd.services."hectic-astroneer-server" = {
      after    = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      path     = with pkgs; [ steamcmd ];
      script   = ''
        echo zalupa
      '';
    };
  };
}
