{
  ...
}:
{ 
  inputs,
  lib,
  config,
  ...
}: let
  cfg = config.hectic.hardware.lenovo-legion;
  hasDisko = false;
in {
  options.hectic.hardware.lenovo-legion = {
    enable = lib.mkEnableOption "Enable lenovo-legion hardware configurations";
    swapSize = lib.mkOption {
      type = lib.types.either (lib.types.enum [ "100%" ]) (lib.types.strMatching "[0-9]+[KMGTP]?");
      default = "0";
      description = ''
        Size of the partition, in sgdisk format.
        sets end automatically with the + prefix
        can be 100% for the whole remaining disk, will be done last in that case.
      '';
    };
    device = lib.mkOption {
      type = lib.types.str;
      default = "0";
      description = ''
        Size of the partition, in sgdisk format.
        sets end automatically with the + prefix
        can be 100% for the whole remaining disk, will be done last in that case.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
  };
}
