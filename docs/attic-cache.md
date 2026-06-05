# Using the `hectic` Attic Cache

This document explains how to:

1. pull build artifacts from the cache
2. push new artifacts to the cache
3. configure this flake to use the cache

## Cache endpoints

- API endpoint: `https://cache.hectic-lab.com`
- Binary cache endpoint: `https://cache.hectic-lab.com/hectic`

The `hectic` cache is:

- public for reads
- private for pushes

## Requirements

Use the Attic client package:

```sh
nix shell nixpkgs#attic-client
```

Or run commands directly with:

```sh
nix shell nixpkgs#attic-client -c <command>
```

## Read from the cache

### Get the cache public key

```sh
nix shell nixpkgs#attic-client -c attic cache info hectic
```

Copy the `Public Key` value, which looks like:

```text
hectic:...
```

### Configure Nix to trust the cache

Per-user: `~/.config/nix/nix.conf`

```ini
substituters = https://cache.nixos.org https://cache.hectic-lab.com/hectic
trusted-public-keys = hectic:PASTE_PUBLIC_KEY_HERE
```

System-wide: `/etc/nix/nix.conf`

```ini
substituters = https://cache.nixos.org https://cache.hectic-lab.com/hectic
trusted-public-keys = hectic:PASTE_PUBLIC_KEY_HERE
```

After that, normal Nix commands can download from the cache automatically:

```sh
nix build .#migrator
nix develop
nix flake check
```

## Use the cache from this flake

You can also advertise the cache from `flake.nix`:

```nix
nixConfig = {
  extra-substituters = [
    "https://cache.nixos.org"
    "https://cache.hectic-lab.com/hectic"
  ];
  extra-trusted-public-keys = [
    "hectic:PASTE_PUBLIC_KEY_HERE"
  ];
};
```

Then users can run:

```sh
nix build --accept-flake-config .#migrator
```

## Log in for pushing

Pushing requires an Attic token.

```sh
nix shell nixpkgs#attic-client -c attic login local https://cache.hectic-lab.com "<TOKEN>"
```

Example with `pass`:

```sh
nix shell nixpkgs#attic-client -c attic login local https://cache.hectic-lab.com "$(pass show atticd/hectic-lab/token)"
```

## Push build results

### Push a package

```sh
nix build .#migrator
nix shell nixpkgs#attic-client -c attic push local:hectic ./result
```

### Push a check

```sh
nix build .#checks.x86_64-linux.arguments
nix shell nixpkgs#attic-client -c attic push local:hectic ./result
```

### Push a NixOS system build

```sh
nix build '.#nixosConfigurations."hectic-lab|x86_64-linux".config.system.build.toplevel'
nix shell nixpkgs#attic-client -c attic push local:hectic ./result
```

## Recommended workflow

### Local development

Use the cache for reads only:

```sh
nix build .#migrator
nix develop
nix flake check
```

### CI / builder

1. Build
2. Push to Attic

Example:

```sh
nix build .#migrator
nix shell nixpkgs#attic-client -c attic push local:hectic ./result
```

## Useful commands

### Show cache info

```sh
nix shell nixpkgs#attic-client -c attic cache info hectic
```

### Check login config

```sh
nix shell nixpkgs#attic-client -c attic cache info local:hectic
```

### Re-login with a new token

```sh
nix shell nixpkgs#attic-client -c attic login local https://cache.hectic-lab.com "<NEW_TOKEN>"
```

## Common issues

### `flake 'nixpkgs' does not provide attribute 'attic'`

Use:

```sh
nix shell nixpkgs#attic-client
```

Not:

```sh
nix shell nixpkgs#attic
```

### `HTTP 413 Payload Too Large`

This means nginx rejected the upload body size. The server must allow large uploads on the Attic vhost.

### Push succeeds for some paths but fails for others

Usually means:

- nginx body size limit
- timeout/reverse proxy issue
- bad token permissions

### Cache pulls do not work

Check:

- `substituters`
- `trusted-public-keys`
- the exact public key from `attic cache info hectic`

## Notes about retention and storage

- The cache currently uses Hetzner Object Storage
- If no `retention-period` is configured, cached objects do not expire automatically
- This is good for long-lived reuse, but storage usage can grow over time

## Summary

### Read access

```sh
nix build .#migrator
```

after configuring:

```ini
substituters = https://cache.nixos.org https://cache.hectic-lab.com/hectic
trusted-public-keys = hectic:PASTE_PUBLIC_KEY_HERE
```

### Push access

```sh
nix shell nixpkgs#attic-client -c attic login local https://cache.hectic-lab.com "<TOKEN>"
nix build .#migrator
nix shell nixpkgs#attic-client -c attic push local:hectic ./result
```
