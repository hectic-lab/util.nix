"""Parse Xray server configuration and extract VLESS parameters."""

import json
from dataclasses import dataclass, field


@dataclass
class VlessClient:
    uuid: str
    email: str = ""
    flow: str = ""


@dataclass
class StreamSettings:
    """Shared connection settings extracted from Xray config."""
    port: int = 443
    security: str = "reality"
    network: str = "tcp"
    sni: str = ""
    short_ids: list[str] = field(default_factory=list)
    flow: str = ""
    fingerprint: str = "chrome"


@dataclass
class VlessServerParams:
    """Connection parameters for one server endpoint."""
    name: str
    address: str
    port: int
    security: str = "reality"
    network: str = "tcp"
    sni: str = ""
    public_key: str = ""
    short_ids: list[str] = field(default_factory=list)
    flow: str = ""
    fingerprint: str = "chrome"


@dataclass
class XrayConfig:
    clients: list[VlessClient]
    stream: StreamSettings


def parse_xray_config(config_path: str) -> XrayConfig:
    """Parse Xray server JSON config and extract clients + stream settings.

    Reads the VLESS inbound to get:
    - Client UUIDs and emails
    - Stream settings (security, network, sni, shortIds, flow, fingerprint)

    Args:
        config_path: Path to the Xray config JSON file.

    Returns:
        XrayConfig with clients and shared stream settings.
    """
    with open(config_path, "r") as f:
        raw = json.load(f)

    inbounds = raw.get("inbounds", [])
    vless_inbound = None
    for inbound in inbounds:
        if inbound.get("protocol") == "vless":
            vless_inbound = inbound
            break

    if vless_inbound is None:
        raise ValueError("No VLESS inbound found in Xray config")

    port = vless_inbound.get("port", 443)

    # Extract stream/security settings
    stream_raw = vless_inbound.get("streamSettings", {})
    network = stream_raw.get("network", "tcp")
    security = stream_raw.get("security", "none")

    sni = ""
    short_ids = []
    fingerprint = "chrome"

    if security == "reality":
        reality = stream_raw.get("realitySettings", {})
        server_names = reality.get("serverNames", [])
        sni = server_names[0] if server_names else ""
        short_ids = reality.get("shortIds", [])
        fingerprint = reality.get("fingerprint", "chrome")
    elif security == "tls":
        tls = stream_raw.get("tlsSettings", {})
        sni = tls.get("serverName", "")

    # Extract clients
    settings = vless_inbound.get("settings", {})
    raw_clients = settings.get("clients", [])
    clients = []
    default_flow = ""
    for c in raw_clients:
        client = VlessClient(
            uuid=c.get("id", ""),
            email=c.get("email", ""),
            flow=c.get("flow", ""),
        )
        if client.uuid:
            clients.append(client)
        if not default_flow and client.flow:
            default_flow = client.flow

    stream = StreamSettings(
        port=port,
        security=security,
        network=network,
        sni=sni,
        short_ids=short_ids,
        flow=default_flow,
        fingerprint=fingerprint,
    )

    return XrayConfig(clients=clients, stream=stream)


def build_servers(
    servers_json: str, stream: StreamSettings,
) -> list[VlessServerParams]:
    """Build server endpoint list from XRAY_SERVERS env + shared stream settings.

    XRAY_SERVERS only needs per-server fields (name, address, public_key).
    Everything else comes from the Xray config stream settings.

    Expected format:
    [
      {"name": "NL", "address": "1.2.3.4", "public_key": "..."},
      {"name": "DE", "address": "5.6.7.8", "public_key": "..."},
    ]

    Optional per-server overrides: port, security, network, sni, short_ids,
    flow, fingerprint (fall back to stream settings if not specified).
    """
    raw = json.loads(servers_json)
    servers = []
    for s in raw:
        server = VlessServerParams(
            name=s["name"],
            address=s["address"],
            port=s.get("port", stream.port),
            security=s.get("security", stream.security),
            network=s.get("network", stream.network),
            sni=s.get("sni", stream.sni),
            public_key=s.get("public_key", ""),
            short_ids=s.get("short_ids", stream.short_ids),
            flow=s.get("flow", stream.flow),
            fingerprint=s.get("fingerprint", stream.fingerprint),
        )
        servers.append(server)
    return servers
