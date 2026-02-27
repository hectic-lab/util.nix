{
  ...
}:
{
  pkgs,
  config,
  ...
}:
{
  sops.secrets."ss-bfs/password" = {};
  services.shadowsocks-rust = {
    enable = true;
    plugin = "${pkgs.shadowsocks-v2ray-plugin}/bin/v2ray-plugin";
    # TODO: setup dnscrypt or a private DNS server for this
    # extraConfig = {
    #   nameserver = "185.12.64.1"; # FIXME: this can vary across instances.
    # };
    port = 55228;
    pluginOpts = "server";
    # TODO: setup a TLS certs for this (look: (README.md) https://github.com/shadowsocks/v2ray-plugin/)
    #pluginOpts = "server;tls;host=ss.bfs.band";
    passwordFile = config.sops.secrets."ss-bfs/password".path;
    mode = "tcp_and_udp"; # default
    localAddress = "0.0.0.0";
    fastOpen = true; # default
    encryptionMethod = "chacha20-ietf-poly1305"; # default
  };
}
