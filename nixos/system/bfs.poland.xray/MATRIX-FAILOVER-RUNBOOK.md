# Matrix Cluster Failover Runbook (`accord.tube`)

Primary: `hectic-lab` (NL, `128.140.75.58`)
Standby: `bfs.poland.xray` (PL, `91.198.166.181`)

Module: `hectic.generic.matrix-cluster` (`nixos/module/generic/matrix-cluster.nix`).
Shared secrets: `sus/matrix-cluster.yaml`.

All `psql` and `pg_ctl` invocations use PostgreSQL **17** at data dir
`/var/lib/postgresql/17`.

## Initial setup

### 1. Provision shared SOPS file (`sus/matrix-cluster.yaml`)

On a workstation with both yukkop and yukkop-alt age keys available:

```sh
sudo cat /var/lib/matrix-synapse/homeserver.signing.key  # on NL (hectic-lab)
# Copy the single line value into the buffer for the next step.

sops sus/matrix-cluster.yaml
```

Populate the editor with:

```yaml
matrix:
  signing-key: <paste verbatim signing-key line from NL>
  postgres-replication-password: <openssl rand -base64 32>
  object-storage:
    credentials: |
      ACCESS_KEY_ID=<verbatim copy from sus/hectic-lab.yaml>
      SECRET_ACCESS_KEY=<verbatim copy from sus/hectic-lab.yaml>
  porkbun-api-key: <PORKBUN_API_KEY>
  porkbun-secret-api-key: <PORKBUN_SECRET_API_KEY>
```

Verify recipients:

```sh
sops updatekeys sus/matrix-cluster.yaml
sops -d sus/matrix-cluster.yaml | grep -E 'signing-key|porkbun-api-key|object-storage'
```

Expected: all five keys present, exit 0.

### 2. Deploy NL primary first

```sh
nixos-rebuild switch --flake .#'hectic-lab|x86_64-linux' --target-host root@128.140.75.58
```

Verify on NL:

```sh
sudo systemctl status matrix-synapse postgresql matrix-cluster-replication-password
sudo -u postgres psql -c "select rolname, rolreplication from pg_roles where rolname='replication';"
# Expected: replication | t
```

### 3. Seed PL replica with `pg_basebackup`

On PL:

```sh
sudo systemctl stop postgresql
sudo rm -rf /var/lib/postgresql/17
sudo -u postgres install -d -m 0700 /var/lib/postgresql/17
sudo -u postgres PGPASSWORD="$(sudo cat /run/secrets/matrix/postgres-replication-password)" \
  pg_basebackup \
    -h 128.140.75.58 \
    -p 5432 \
    -U replication \
    -D /var/lib/postgresql/17 \
    -Fp -Xs -P -R \
    --no-password
```

`-R` writes `standby.signal` and an initial `primary_conninfo`. The
matrix-cluster module's `matrix-cluster-standby-bootstrap` service will
overwrite `primary_conninfo` to use a libpq passfile on next boot.

### 4. Deploy PL standby

```sh
nixos-rebuild switch --flake .#'bfs.poland.xray|x86_64-linux' --target-host root@91.198.166.181
sudo systemctl start postgresql
```

Verify streaming on NL:

```sh
sudo -u postgres psql -c 'select client_addr, state, sync_state from pg_stat_replication;'
# Expected: 91.198.166.181 | streaming | async
```

Verify standby on PL:

```sh
sudo -u postgres psql -c 'select pg_is_in_recovery();'
# Expected: t
sudo systemctl is-active matrix-synapse
# Expected: inactive (standby keeps Synapse off)
```

### 5. Remove duplicate S3 credentials from `sus/hectic-lab.yaml`

Only AFTER NL is confirmed healthy reading from the new shared file:

```sh
sops sus/hectic-lab.yaml
# Delete the matrix/object-storage/credentials block.
sudo nixos-rebuild switch --flake .#'hectic-lab|x86_64-linux'
```

## Normal operations

```sh
# NL: replication health
sudo -u postgres psql -c 'select * from pg_stat_replication;'
# Expected: 1 row, state=streaming, sync_state=async

# PL: replay status
sudo -u postgres psql -c 'select now() - pg_last_xact_replay_timestamp() as lag;'

# Both: cert renewal
sudo systemctl status acme-accord.tube.timer
sudo journalctl -u acme-accord.tube.service --since '24 hours ago'

# Synapse health (NL primary)
curl -sf https://accord.tube/_matrix/client/versions | head
```

## Planned failover (NL -> PL)

```sh
# 1. Drain NL: stop accepting writes.
sudo systemctl stop matrix-synapse
sudo systemctl stop postgresql   # ensure no new WAL after this point

# 2. Promote PL replica.
sudo -u postgres pg_ctl -D /var/lib/postgresql/17 promote
# Wait until pg_is_in_recovery() returns f:
sudo -u postgres psql -c 'select pg_is_in_recovery();'

# 3. Make the role switch declarative before rebuilding.
#    Edit the flake so rebuilds match the promoted database state:
#      - nixos/system/bfs.poland.xray/bfs.poland.xray.nix:
#          hectic.generic.matrix-cluster.role = "primary";
#          hectic.generic.matrix-cluster.overrideEnableSynapse = true;
#          hectic.generic.matrix-cluster.secretsFile = config.sops.secrets."matrix/secrets".path;
#      - nixos/system/hectic-lab/hectic-lab.nix:
#          hectic.generic.matrix-cluster.role = "standby";
#          hectic.generic.matrix-cluster.overrideEnableSynapse = false;
#          hectic.generic.matrix-cluster.replication.peerHost = "91.198.166.181";
#          hectic.generic.matrix-cluster.replication.allowedSourceIPs = [ "128.140.75.58/32" ];
#    (You will also need a matrix/secrets entry on PL - copy from NL via SOPS.)
sudo nixos-rebuild switch --flake .#'bfs.poland.xray|x86_64-linux'
sudo nixos-rebuild switch --flake .#'hectic-lab|x86_64-linux'
sudo systemctl status matrix-synapse

# 4. Swap DNS A record at Porkbun:
#    accord.tube  A  91.198.166.181   (was 128.140.75.58)
#    TTL: set to 300 in advance of any planned failover.
#    Porkbun UI: https://porkbun.com/account/domainsSpeedy -> accord.tube -> DNS -> edit A record.
#    Or via API:
sudo curl -sX POST https://api.porkbun.com/api/json/v3/dns/editByNameType/accord.tube/A \
  -H 'content-type: application/json' \
  -d "$(jq -n --arg k "$PORKBUN_API_KEY" --arg s "$PORKBUN_SECRET_API_KEY" \
        '{secretapikey:$s,apikey:$k,content:"91.198.166.181",ttl:"300"}')"

# 5. Federation smoke test.
curl -s 'https://federationtester.matrix.org/api/report?server_name=accord.tube' | jq .FederationOK
# Expected: true
```

Expected after the rebuilds:

- `bfs.poland.xray` evaluates and runs as `role = "primary"`.
- `hectic-lab` evaluates as `role = "standby"` with Synapse forced off.
- Future `nixos-rebuild` runs preserve the promoted topology instead of reapplying standby settings to PL.

## Failback (PL -> NL)

```sh
# 1. Stop NL postgres if still up; clear its data dir.
sudo systemctl stop postgresql matrix-synapse
sudo rm -rf /var/lib/postgresql/17

# 2. Re-seed NL from PL (now the live primary).
sudo -u postgres install -d -m 0700 /var/lib/postgresql/17
sudo -u postgres PGPASSWORD="$(sudo cat /run/secrets/matrix/postgres-replication-password)" \
  pg_basebackup -h 91.198.166.181 -p 5432 -U replication \
    -D /var/lib/postgresql/17 -Fp -Xs -P -R --no-password

# 3. Temporarily flip roles in the flake:
#    - hectic-lab.nix: role = "standby";   peerHost = "91.198.166.181";
#    - bfs.poland.xray.nix: role = "primary"; peerHost = "128.140.75.58";
#    Rebuild both.

# 4. Once NL is streaming green, do the reverse failover dance:
sudo systemctl stop matrix-synapse                    # on PL
sudo -u postgres pg_ctl -D /var/lib/postgresql/17 promote   # on NL
# Then revert the flake role assignments back to NL=primary / PL=standby and
# rebuild both hosts.

# 5. Swap DNS back at Porkbun (A -> 128.140.75.58).
```

## Disaster recovery (NL permanently lost)

```sh
# 1. Promote PL as the new permanent primary.
sudo -u postgres pg_ctl -D /var/lib/postgresql/17 promote

# 2. Edit nixos/system/bfs.poland.xray/bfs.poland.xray.nix:
#      hectic.generic.matrix-cluster.role = "primary";
#      hectic.generic.matrix-cluster.overrideEnableSynapse = lib.mkForce null;
#      hectic.generic.matrix-cluster.replication.peerHost = "<new-standby-ip>";
#      hectic.generic.matrix-cluster.replication.allowedSourceIPs = [ "<new-standby-ip>/32" ];

# 3. Provision a new host (any region with Porkbun-managed DNS) and import
#    self.nixosModules.matrix-cluster with role = "standby" pointed at PL's IP.

# 4. Bootstrap the new standby via pg_basebackup from PL exactly as in
#    "Initial setup" step 3, replacing 128.140.75.58 with PL's IP.

# 5. Update Porkbun A record to PL's IP permanently.
```
