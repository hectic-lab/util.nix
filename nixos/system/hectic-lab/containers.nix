{
  inputs ? null,
  flake ? null,
  self ? null,
  ...
}:
{
  config ? null,
  pkgs ? null,
  lib ? null,
  modulesPath ? null,
  ...
}:
with builtins;
with lib;
# with inputs.dream.lib;
let
in {

  # networking.nat = {
  #   enable = true;
  #   internalInterfaces = [ "ve-+" ];
  #   externalInterface = "lo";
  #   # Lazy IPv6 connectivity for the container
  #   enableIPv6 = true;
  # };

  # containers.webserver = {
  #   autoStart = true;
  #   privateNetwork = true;
  #   hostAddress = "192.168.115.10";
  #   localAddress = "192.168.115.11";
  #   hostAddress6 = "fc00::1";
  #   localAddress6 = "fc00::2";
  #   config = import "${inputs.quteproxy}/nixos/system/quteproxy-staging/quteproxy-staging.nix" {
  #     self   = inputs.quteproxy;
  #     inputs = inputs.quteproxy.inputs;
  #     flake  = inputs.quteproxy;
  #   };
  # };

  # environment.etc.nixos.source = self;
  # boot.kernelModules = [ "kvm" ];

  # microvm.autostart = [
  #   "myvm1"
  # ];
  # microvm.vms = {
  #   myvm1 = {
  #     flake = self;
  #     updateFlake = "git+file:///etc/nixos";
  #   };
  # };
  # microvm = {
  #   mem = 1024*3;
  #   vcpu = 4;
  #   storeOnDisk = false;
  #   shares = [
  #     {
  #       proto = "9p";
  #       # securityModel = "mapped";
  #       tag = "ro-store";
  #       source = "/nix/store";
  #       mountPoint = "/nix/.ro-store";
  #     }
  #     {
  #       proto = "9p";
  #       securityModel = "mapped";
  #       tag = "fsRoot";
  #       source = "/media/pool/mythos/vm/work/vproxy/pr";
  #       mountPoint = "/home/devbox-user/pr";
  #     }
  #   ];
  #   interfaces = [
  #     {
  #       type = "user";
  #
  #       # interface name on the host
  #       id = "vm-seht";
  #
  #       # Ethernet address of the MicroVM's interface, not the host's
  #       # Locally administered have one of 2/6/A/E in the second nibble.
  #       mac = "02:00:00:00:00:01";
  #     }
  #   ];
  #   forwardPorts = [
  #     { from = "host"; host.port = 40500; guest.port = 22; }
  #   ];
  #
  #   writableStoreOverlay = "/nix/.rw-store";
  #   volumes = [
  #     {
  #       autoCreate = true;
  #       size = 1024*32;
  #
  #       image = "/media/pool/mythos/vm/work/vproxy/nix-store-overlay.img";
  #       mountPoint = config.microvm.writableStoreOverlay;
  #     }
  #     {
  #       autoCreate = true;
  #       size = 1024*32;
  #
  #       image = "/media/pool/mythos/vm/work/vproxy/root.img";
  #       mountPoint = "/";
  #     }
  #   ];
  # };
}
