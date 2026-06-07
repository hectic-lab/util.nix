# Gitea runner Nix image

The repo-owned Nix-capable job image is built by the flake package
`gitea-runner-nix-image`.

```sh
nix build .#gitea-runner-nix-image
```

The package currently emits a Docker archive tagged:

```text
gitea-runner-nix-image:2026-06-07
```

After publishing to the internal registry, map the `nix` runner label to the
published, immutable image reference:

```text
nix:docker://gitea.hectic-lab.com/hectic-lab/gitea-runner-nix-image:2026-06-07
```

Task 7 should replace the tag-only reference with the published digest once the
image is pushed, for example
`gitea.hectic-lab.com/hectic-lab/gitea-runner-nix-image@sha256:<digest>`.

Keep `ubuntu-latest` on the `gitea/runner` default image unless a later runner
configuration task explicitly changes it. Only the `nix` label should select
this custom image.

## Image contents

The image includes `nix`, `git`, `bash`, `coreutils`, and `cacert`. Its
`/etc/nix/nix.conf` enables flakes and configures the repo substituters from the
top-level `flake.nix`:

```text
experimental-features = nix-command flakes
substituters = https://cache.nixos.org https://cache.hectic-lab.com/hectic
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gW4x6l1xP+GxgH0r7u+f6p1VFlr0= hectic:KMQsKow4SoA9K2vOJlOljmx7/Zpf91Yy+5qEtxDDCzA=
sandbox = false
```

No Gitea runner token, SSH key, SOPS key, kubeconfig, Hetzner token, or S3
credential belongs in this image. Runtime secrets stay with the Kubernetes
runner configuration and token-file mount contract.
