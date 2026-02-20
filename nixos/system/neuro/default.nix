{
  flake,
  self,
  inputs,
  system,
  ...
}: let
  # Use folder name as name of this system
  name = builtins.baseNameOf ./.;

in self.lib.nixpkgs-lib.nixosSystem {
  pkgs = import inputs.nixpkgs { 
    inherit system;
    overlays = [
      self.overlays.default
      inputs.nix-minecraft.overlay
    ];
    config.allowUnfreePredicate = pkg: builtins.elem (self.lib.nixpkgs-lib.getName pkg) [
      "minecraft-server"
      "nvidia-x11"

      "cuda_nvcc"
      "cuda_cudart"
      "cuda_cuobjdump"
      "cuda_cupti"
      "cuda_nvdisasm"
      "cuda_cccl"
      "cuda_nvml_dev"
      "cuda_nvrtc"
      "cuda_nvtx"
      "cuda_profiler_api"

      "libcusparse_lt"
      "libcublas"
      "libcufft"
      "libcufile"
      "libcurand"
      "libcusolver"
      "libnvjitlink"
      "libcusparse"
      "cudnn"
    ];
  };
  modules = [
    { networking.hostName = name; }
    (import ./${name}.nix { inherit flake self inputs; })
    inputs.nix-minecraft.nixosModules.minecraft-servers
  ];
}
