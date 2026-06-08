{ pkgs, ... }: let
  opentofuUnstable = "github:NixOS/nixpkgs/nixos-unstable#opentofu";

  tofu = pkgs.writeShellScriptBin "tofu" ''
    exec ${pkgs.nix}/bin/nix run ${opentofuUnstable} -- "$@"
  '';

  giteaRunnersSetup = pkgs.writeShellScriptBin "gitea-runners-setup" /* sh */ ''
    cat <<'EOF'
Gitea runners setup checklist

Tools available in this shell:
  tofu, kubectl, kustomize, kubeconform, sops, age, awscli2, hcloud, tea,
  docker, skopeo, go-containerregistry, jq, yq-go, curl, git, openssh, nix

Environment expected before real deploy/apply:
  TF_VAR_hcloud_token
  TF_VAR_ssh_public_key
  TF_VAR_ssh_private_key
  S3 backend credentials and endpoint access
  a matching SOPS age identity for sus/gitea-runners.yaml
  kubectl access to the target cluster
  a concrete registry digest for the pushed Nix-capable runner image if enabling
  the nix label

OpenTofu validation gate:
  tofu version
  tofu -chdir=infra/gitea-runners/opentofu validate

Nix image build/publish/digest gate:
  nix build .#gitea-runner-nix-image
  publish the archive, then pin the registry-reported digest in the runner label
  mapping
  nix:docker://gitea.hectic-lab.com/hectic-lab/gitea-runner-nix-image@sha256:<registry-digest>

SOPS token Secret creation gate:
  kubectl apply -f infra/gitea-runners/k8s/namespace.yaml
  umask 077
  token_file=$(mktemp /tmp/gitea-runner-token.XXXXXX)
  trap 'rm -f "$token_file"' EXIT
  sops -d --extract '["gitea"]["hectic-lab"]["org-runner-registration-token"]' sus/gitea-runners.yaml > "$token_file"
  kubectl -n gitea-runners create secret generic gitea-runner-token \
    --from-file=token="$token_file" \
    --dry-run=client \
    -o yaml | kubectl -n gitea-runners apply -f -

Cluster provision gate:
  tofu -chdir=infra/gitea-runners/opentofu init
  tofu -chdir=infra/gitea-runners/opentofu validate
  tofu -chdir=infra/gitea-runners/opentofu plan -out=.sisyphus/evidence/task-12-deploy.plan
  tofu -chdir=infra/gitea-runners/opentofu apply .sisyphus/evidence/task-12-deploy.plan
  export KUBECONFIG="$(tofu -chdir=infra/gitea-runners/opentofu output -raw kubeconfig_path)"

Kubernetes apply gate:
  kubectl config current-context
  kubectl get nodes -o wide
  kubectl get sc
  kubectl apply -k infra/gitea-runners/k8s

Verification commands:
  kubectl -n gitea-runners get statefulset gitea-runner
  kubectl -n gitea-runners rollout status statefulset/gitea-runner --timeout=10m
  kubectl -n gitea-runners get pods -l app.kubernetes.io/name=gitea-runner -o wide
  kubectl -n gitea-runners get pvc -l app.kubernetes.io/name=gitea-runner -o wide
  kubectl -n gitea-runners get events --sort-by=.lastTimestamp | tail -n 50
  kubectl -n gitea-runners logs statefulset/gitea-runner -c runner --tail=200

Main blockers and gates:
  do not run tofu apply without all external inputs
  do not apply the k8s overlay until the gitea-runner-token Secret exists
  do not enable the nix label until the image has been published with a concrete digest
  do not print, load, or require secrets on shell entry
EOF
  '';
in pkgs.mkShell {
  name = "gitea-runners";

  buildInputs = [
    tofu
    giteaRunnersSetup
    pkgs.nix
    pkgs.kubectl
    pkgs.kustomize
    pkgs.kubeconform
    pkgs.sops
    pkgs.age
    pkgs.awscli2
    pkgs.hcloud
    pkgs.tea
    pkgs.docker
    pkgs.skopeo
    pkgs.go-containerregistry
    pkgs.jq
    pkgs.yq-go
    pkgs.curl
    pkgs.git
    pkgs.openssh
  ];

  shellHook = ''
    export GITEA_RUNNERS_ROOT="$PWD/infra/gitea-runners"
    export GITEA_RUNNERS_TOFU_DIR="$GITEA_RUNNERS_ROOT/opentofu"
    export GITEA_RUNNERS_K8S_DIR="$GITEA_RUNNERS_ROOT/k8s"
    export GITEA_RUNNERS_IMAGE_DIR="$GITEA_RUNNERS_ROOT/image"
    export GITEA_RUNNERS_NAMESPACE="gitea-runners"

    alias cd-gitea-runners='cd "$GITEA_RUNNERS_ROOT"'
    alias cd-gitea-runners-tofu='cd "$GITEA_RUNNERS_TOFU_DIR"'
    alias cd-gitea-runners-k8s='cd "$GITEA_RUNNERS_K8S_DIR"'

    echo ""
    echo "=== Gitea runner setup DevShell ==="
    echo ""
    echo "Run gitea-runners-setup for the full setup checklist."
    echo "Paths: "
    echo "  root=$GITEA_RUNNERS_ROOT"
    echo "  tofu=$GITEA_RUNNERS_TOFU_DIR"
    echo "  k8s=$GITEA_RUNNERS_K8S_DIR"
    echo "  image=$GITEA_RUNNERS_IMAGE_DIR"
    echo ""
  '';
}
