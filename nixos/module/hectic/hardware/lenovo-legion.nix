{
  ...
}:
{ 
  inputs,
  lib,
  config,
  modulesPath,
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
    imports = [
      (modulesPath + "/installer/scan/not-detected.nix")

      "${inputs.nixos-hardware}/common/cpu/amd"
      "${inputs.nixos-hardware}../../../common/cpu/amd/pstate.nix"
      "${inputs.nixos-hardware}../../../common/gpu/amd"
      "${inputs.nixos-hardware}../../../common/gpu/nvidia/prime-sync.nix"
      "${inputs.nixos-hardware}../../../common/pc/laptop"
      "${inputs.nixos-hardware}../../../common/pc/laptop/ssd"
    ];

    hardware.nvidia = {
      modesetting.enable = true;
      prime = {
        amdgpuBusId = "PCI:5:0:0";
        nvidiaBusId = "PCI:1:0:0";
      };
    };
    
  environment.systemPackages = with pkgs; [
    vulkan-tools
  ];

  /* boot */
  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "usb_storage" "usbhid" "sd_mod" ];
  boot.initrd.kernelModules = [ "dm-snapshot" "amdgpu" ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  /* */
  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  /* cpu */
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  /* nvidia */
  services.xserver.videoDrivers = [ 
    "nvidia" 
    #"amdgpu"  # NOTE: probably useles with nvidia optimus prime
    #"nouveau" # NOTE: open source nvidia
  ];

  hardware.opengl = {
    enable = true;
    driSupport = true;
    driSupport32Bit = true;
    extraPackages = with pkgs; [
      vulkan-loader
      vulkan-validation-layers
      vulkan-extension-layer
      amdvlk

    ];
    extraPackages32 = with pkgs; [
      pkgsi686Linux.vulkan-loader
      pkgsi686Linux.vulkan-validation-layers
      pkgsi686Linux.vulkan-extension-layer
      driversi686Linux.amdvlk
    ];
  };

  #environment.variables.VK_DRIVER_FILES=/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json;
  #environment.sessionVariables.VK_DRIVER_FILES = "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json";

  #environment.sessionVariables = rec {
  #  VK_ICD_FILENAMES = 
  #    "${config.hardware.nvidia.package}/share/vulkan/icd.d/nvidia_icd.x86_64.json";

  #    #:${config.environment.variables.VK_ICD_FILENAMES or ""}";
  #};


  hardware.nvidia = {
    # Modesetting is required.
    modesetting.enable = true;

    # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
    # Enable this if you have graphical corruption issues or application crashes after waking
    # up from sleep. This fixes it by saving the entire VRAM memory to /tmp/ instead 
    # of just the bare essentials.
    powerManagement.enable = false;

    # Fine-grained power management. Turns off GPU when not in use.
    # Experimental and only works on modern Nvidia GPUs (Turing or newer).
    powerManagement.finegrained = false;

    # Use the NVidia open source kernel module (not to be confused with the
    # independent third-party "nouveau" open source driver).
    # Support is limited to the Turing and later architectures. Full list of 
    # supported GPUs is at: 
    # https://github.com/NVIDIA/open-gpu-kernel-modules#compatible-gpus 
    # Only available from driver 515.43.04+
    # Currently alpha-quality/buggy, so false is currently the recommended setting.
    open = false;

    # Enable the Nvidia settings menu,
    # accessible via `nvidia-settings`.
    nvidiaSettings = true;

    # nvidia package overwrive
    package = config.boot.kernelPackages.nvidiaPackages.stable;

  };

  /* sound */
  hardware.pulseaudio.enable = true;
  hardware.pulseaudio.support32Bit = true;

  };
}
