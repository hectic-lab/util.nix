{ ... }:
{
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.graphics.enable = true;
  hardware.nvidia = {
    open = false;
    nvidiaSettings = false;
    modesetting.enable = false;
  };
}
