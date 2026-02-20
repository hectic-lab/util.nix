{
  pkgs,
  ...
}: 
{
  services.minecraft-servers = {
    enable = true;
    eula = true;
    openFirewall = true;

    servers.vanilla = {
      enable = true;
      jvmOpts = "-Xmx6G -Xms2G";
      package = pkgs.minecraftServers.vanilla-1_21_11;

      serverProperties = {
        difficulty = "hard";
	online-mode = true;
	view-distance = 32;
	level-seed = "8306359138650378643";
	pause-when-empty-seconds = 0;
      };
    };
  };
}
