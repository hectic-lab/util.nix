# Spec: sentinella-p2p-design

Scope: feature

# sentinèlla P2P Design Spec

## Goal
Replace the hub-and-spoke sentinel topology with a fully peer-to-peer model where every node is equal.

## Topology
- Every node runs both `probe` and `watcher`
- No privileged coordinator; any node can go down without breaking monitoring of the others
- Duplicate Telegram alerts from multiple nodes detecting the same failure are **accepted** (reliability over deduplication)

## Peer Discovery — DNS multi-A record
- One DNS name (e.g. `peers.sentinella.com`) has multiple A records, one per node IP
- Configured externally via any DNS registrar (Cloudflare, Namecheap, etc.)
- Recommended TTL: **60 seconds** so new nodes propagate quickly
- Each watcher resolves the name via `getent hosts $PEERS_DNS` on every poll cycle
- Own IP (`$SELF`) is stripped from the result so a node never polls itself
- No per-node DNS names needed; IP addresses are used directly in peer URLs

```
peers.sentinella.com  A  1.2.3.4    TTL 60
peers.sentinella.com  A  5.6.7.8    TTL 60
peers.sentinella.com  A  9.10.11.12 TTL 60
```

## Environment Variables

### watcher (new, replaces sentinel)
| Variable | Default | Required | Description |
|---|---|---|---|
| `PEERS_DNS` | — | yes | DNS name resolving to all peer IPs |
| `SELF` | — | yes | This node's own IP; excluded from peer list |
| `PEERS_PORT` | `5988` | no | Port all peers listen on |
| `PEERS_SCHEME` | `http` | no | URL scheme for peer connections |
| `PEERS_TOKEN` | — | no | Single Basic Auth token sent to all peers (replaces per-server TOKENS) |
| `TG_TOKEN` | — | yes | Telegram bot token |
| `TG_CHAT_ID` | — | yes | Telegram chat ID |
| `TIMEOUT` | `5` | no | curl timeout seconds |
| `POLLING_INTERVAL_SEC` | `3` | no | Seconds between poll rounds |
| `STATE_DIR` | `/var/lib/sentinel` | no | Directory for state files |
| `SPAM` | `0` | no | If 1, notify on every poll |

### probe / router (unchanged)
| Variable | Default | Description |
|---|---|---|
| `PORT` | `5988` | TCP port to listen on |
| `URLS` | — | Space-separated URLs to health-check |
| `VOLUMES` | all from df -P | Mount points to report |
| `TIMEOUT` | `5` | curl timeout |
| `AUTH_FILE` | — | Path to user:pass auth file |

## Key Implementation Details

### resolve_peers() in watcher.sh
```sh
resolve_peers() {
  getent hosts "$PEERS_DNS" \
    | awk '{print $1}' \
    | grep -v "^${SELF}$" \
    | awk -v s="$PEERS_SCHEME" -v p="$PEERS_PORT" '{print s"://"$1":"p}'
}
```
Called at the top of every outer poll loop iteration — no restart needed when DNS changes.

### Auth simplification
- Old: per-server CSV `TOKENS` aligned with `SERVERS`
- New: single optional `PEERS_TOKEN`; either all peers require auth or none do

### State files
- Unchanged: `$STATE_DIR/$(cksum url).state` contains last known state string
- Format: `up:N/M:200` or `down:0/0:000`

## Binaries
| Old name | New name | Role |
|---|---|---|
| `sentinel` | `watcher` | Polls peers, sends alerts |
| `probe` | `probe` | socat TCP listener (unchanged) |
| `router` | `router` | HTTP handler (unchanged + auth bug fixed) |
| `base64` | `base64` | awk base64 util (unchanged) |

## NixOS Module Options
```
hectic.sentinella.enable            bool
hectic.sentinella.peersDns          string   # e.g. "peers.sentinella.com"
hectic.sentinella.self              string   # this node's own IP
hectic.sentinella.port              int      # default 5988
hectic.sentinella.urls              [string] # URLs for probe to health-check
hectic.sentinella.volumes           [string] # mount points for probe
hectic.sentinella.tgToken           string
hectic.sentinella.tgChatId          string
hectic.sentinella.pollingIntervalSec int     # default 3
```
Generates two systemd services: `sentinella-probe` and `sentinella-watcher`.

## Known Bug to Fix (router.sh)
The Basic Auth check references `$USER` and `$PASS` which are never populated.
Fix: move `auth_ok=false` before the header loop and compare `$tok` against
each entry in `$AUTH_TOKENS` (which is correctly populated from `AUTH_FILE`).