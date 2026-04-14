{
  system,
  pkgs,
  self,
}: let
  proxychainsConf = pkgs.writeText "proxychains.conf" ''
    strict_chain
    proxy_dns
    tcp_read_time_out 15000
    tcp_connect_time_out 8000
    [ProxyList]
    socks5 127.0.0.1 1080
  '';

  # Wrapper script for profanity with proxy
  profanity-proxy = pkgs.writeShellScriptBin "profanity-proxy" ''
    exec ${pkgs.proxychains-ng}/bin/proxychains4 -f ${proxychainsConf} ${pkgs.profanity}/bin/profanity "$@"
  '';
in pkgs.mkShell {
  buildInputs = [
    pkgs.profanity
    pkgs.proxychains-ng
    profanity-proxy
  ];

  shellHook = ''
    echo ""
    echo "=== XMPP DevShell ==="
    echo ""
    echo "1. Start SSH SOCKS proxy (in another terminal):"
    echo "   ssh -D 1080 -N neuro"
    echo ""
    echo "2. Run profanity with proxy:"
    echo "   profanity-proxy"
    echo ""
    echo "3. In profanity:"
    echo "   /connect yukkop@accord.tube"
    echo ""
  '';
}
