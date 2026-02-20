"""VLESS link generation."""

from urllib.parse import urlencode

from .config import VlessServerParams


def generate_vless_link(
    uuid: str,
    server: VlessServerParams,
    remark: str = "",
) -> str:
    """Generate a VLESS share link.

    Format: vless://uuid@address:port?params#remark
    """
    params = {
        "type": server.network,
        "security": server.security,
    }

    if server.security == "reality":
        if server.sni:
            params["sni"] = server.sni
        if server.public_key:
            params["pbk"] = server.public_key
        if server.short_ids:
            params["sid"] = server.short_ids[0]
        if server.fingerprint:
            params["fp"] = server.fingerprint
        if server.flow:
            params["flow"] = server.flow
    elif server.security == "tls":
        if server.sni:
            params["sni"] = server.sni

    query = urlencode(params)
    fragment = remark or f"{server.address}:{server.port}"

    return f"vless://{uuid}@{server.address}:{server.port}?{query}#{fragment}"
