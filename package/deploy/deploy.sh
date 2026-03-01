# requirements: ssh-to-age nixos-anywhere hcloud

HECTIC_NAMESPACE="deploy"

help() {
  # shellcheck disable=SC2059
  printf "$(cat <<EOF
${BGREEN}Usage:$NC deploy COMMAND [OPTIONS] [-- NIX-ARGS...]

deploy - Deploy NixOS configurations to remote hosts via nixos-rebuild or nixos-anywhere.
         Supports ephemeral Hetzner Cloud build servers for builds that cannot run locally.

${BGREEN}Commands:
    ${BCYAN}push$NC                Deploy a NixOS configuration to a target host
    ${BCYAN}rollback$NC            Roll back the target host to a previous generation
    ${BCYAN}history$NC             Show profile generation history on the target host

${BGREEN}Global Options:
    ${BCYAN}--target-host ${CYAN}HOST$NC   SSH address of the target machine (required)
                        Examples: root@192.0.2.1  root@my-server.example.com

${BGREEN}Push Options:
    ${BCYAN}--init$NC               First-time deployment: bootstrap NixOS via nixos-anywhere.
                        Prints the server age public key after provisioning for use in SOPS.
    ${BCYAN}--via-hetzner$NC        Rent an ephemeral Hetzner Cloud server to perform the build,
                        then destroy it when done. Useful when the build cannot run locally
                        (e.g. large CUDA closures like torchWithCuda).

${BGREEN}Push --via-hetzner Options:
    ${BCYAN}--hcloud-token ${CYAN}TOKEN$NC
                        Hetzner Cloud API token. Defaults to \$HCLOUD_TOKEN env variable.
    ${BCYAN}--builder-type ${CYAN}TYPE$NC
                        Hetzner server type for the build machine (default: cx52).
                        cx52 provides 8 vCPU and 32 GB RAM, sufficient for most large builds.
    ${BCYAN}--builder-location ${CYAN}LOC$NC
                        Hetzner datacenter location (default: nbg1).
                        Available: nbg1, fsn1, hel1, ash, hil, sin.
    ${BCYAN}--builder-flake ${CYAN}REF$NC
                        Flake reference for the builder NixOS configuration.
                        Default: github:hectic-lab/util.nix/<git-HEAD-rev>#hetzner-builder|x86_64-linux
                        Override if deploying from a detached HEAD or a fork.
    ${BCYAN}--builder-ssh-key ${CYAN}PATH$NC
                        Path to the private SSH key matching the builder NixOS config
                        (default: ~/.ssh/hetzner-builder).
                        Generate once: ssh-keygen -t ed25519 -f ~/.ssh/hetzner-builder

${BGREEN}Rollback Options:
    ${BCYAN}--to ${CYAN}GEN$NC            Roll back to a specific generation number.
                        If omitted, rolls back to the previous generation.

${BGREEN}Nix Pass-through:
    ${BCYAN}--$NC                   Everything after -- is forwarded verbatim to nixos-rebuild
                        or nixos-anywhere. Use this to pass --flake, --option, etc.
                        Example: deploy push --target-host root@host -- --flake .#"neuro|x86_64-linux"

${BGREEN}Examples:
    ${BBLACK}# Regular push (target must already be NixOS)$NC
    deploy push --target-host root@neuro -- --flake .#"neuro|x86_64-linux"

    ${BBLACK}# First-time bootstrap of a new server$NC
    deploy push --init --target-host root@1.2.3.4 -- --flake .#"games|x86_64-linux"

    ${BBLACK}# Build on an ephemeral Hetzner server (for heavy builds like CUDA)$NC
    deploy push --via-hetzner --target-host root@neuro -- --flake .#"neuro|x86_64-linux"

    ${BBLACK}# Same, with explicit token and a larger builder$NC
    deploy push --via-hetzner --hcloud-token \$TOKEN --builder-type cx62 \\
        --target-host root@neuro -- --flake .#"neuro|x86_64-linux"

    ${BBLACK}# Roll back to the previous generation$NC
    deploy rollback --target-host root@neuro

    ${BBLACK}# Roll back to a specific generation$NC
    deploy rollback --to 42 --target-host root@neuro

    ${BBLACK}# Show generation history$NC
    deploy history --target-host root@neuro

${BGREEN}Exit Codes:$NC
    0    Success
    1    Generic error
    2    Ambiguous arguments
    3    Missing required argument or variable

${BGREEN}Environment Variables:$NC
    ${BBLACK}HCLOUD_TOKEN$NC        Hetzner Cloud API token (used by --via-hetzner)
EOF
)"
}

# ssh proxydoe 'cat /etc/os-release 2>/dev/null || echo "no /etc/os-release"' | grep '^NAME=NixOS$'
# NAME=NixOS

# ssh that not saves the host in ~/.ssh/known_hosts
puressh() {
  # shellcheck disable=SC2068
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $@
}

# echo <gens_list> | find_older_gen(gen)
find_older_gen() {
  local gen="${1:?}"
  grep -oP '(?<=system-)\d+(?=-link)' \
    | sort -n \
    | awk -v n="$gen" '$1 < n {older=$1} END{if(older) print older}'
}

# wait_for_ssh <host>  -- poll until SSH is reachable
wait_for_ssh() {
  local host="${1:?}"
  log info "waiting for ${host} to become reachable via ssh..."
  while ! puressh "$host" true 2>/dev/null; do
    sleep 5
  done
  log info "${host} is reachable"
}

saved_args="$*"

# Show help if no arguments
[ $# -eq 0 ] && { help; exit 0; }

# parse command and independent params
while [ $# -gt 0 ]; do
  case $1 in
    help|--help|-h)
      help
      exit 0
      ;;
    push)
      if [ ${founded_command+x} ]; then
        # shellcheck disable=SC2016
        log error "ambiguous subcommand \`$1\` and \`$founded_command\`"
        exit 2
      fi

      push_deploy=1
      founded_command="$1"
      shift
      ;;
    rollback)
      if [ ${founded_command+x} ]; then
        # shellcheck disable=SC2016
        log error "ambiguous subcommand \`$1\` and \`$founded_command\`"
        exit 2
      fi

      rollback_deploy=1
      founded_command="$1"
      shift
      ;;
    history)
      if [ ${founded_command+x} ]; then
        # shellcheck disable=SC2016
        log error "ambiguous subcommand \`$1\` and \`$founded_command\`"
        exit 2
      fi

      server_history=1
      founded_command="$1"
      shift
      ;;
    --target-host)
      target_host=$2
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      shift
      ;;
  esac
done

# shellcheck disable=SC2086
set -- $saved_args

# parse sub params
while [ $# -gt 0 ]; do
  case $1 in
    --init)
      if [ ${push_deploy+x} ]; then
        server_init=1
      else
        log warn "illegal $1"
      fi
      shift
      ;;
    --to)
      if [ ${rollback_deploy+x} ]; then
        rollback_to="$2"
      else
        log warn "illegal $1"
      fi
      shift 2
      ;;
    # -- via-hetzner flags (only meaningful with push) --
    --via-hetzner)
      if [ ${push_deploy+x} ]; then
        via_hetzner=1
      else
        log warn "illegal $1"
      fi
      shift
      ;;
    --hcloud-token)
      hcloud_token="$2"
      shift 2
      ;;
    --builder-type)
      builder_type="$2"
      shift 2
      ;;
    --builder-location)
      builder_location="$2"
      shift 2
      ;;
    --builder-flake)
      builder_flake="$2"
      shift 2
      ;;
    --builder-ssh-key)
      builder_ssh_key="$2"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      shift
      ;;
  esac
done

# NOTE(yukkop):
# after "end of arguments" (--)
# need to parse nix argument `--target-host`
# without lost of $@, that can be ruined by `shift`
saved_nix_args="$*"

while [ $# -gt 0 ]; do
  case $1 in
    --target-host)
      if [ "${target_host+x}" ] && [ "$target_host" != "$2" ]; then
        log error "you specified 2 ambiguous target hosts \`$target_host\` and \`$2\`"
        exit 2
      fi

      target_host="$2"
      break
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

# NOTE: restore original args
# shellcheck disable=SC2086
set -- $saved_nix_args

if ! [ ${target_host+x} ]; then
  log error "$(printf '%s' '--target-host') not set, but required"
  exit 3
fi

if puressh "$target_host" 'cat /etc/os-release 2>/dev/null || echo "no /etc/os-release"' \
  | grep -q '^NAME=NixOS$'
then
  is_target_host_nixos=1
else
  is_target_host_nixos=0
fi

if [ "${rollback_deploy+x}" ]; then
  if ! [ "${rollback_to+x}" ]; then
    current_gen=$(puressh "$target_host" readlink /nix/var/nix/profiles/system \
      | sed -n 's/^system-\([0-9]\+\)-link$/\1/p')

    rollback_to=$(puressh "$target_host" ls /nix/var/nix/profiles | find_older_gen "$current_gen")

    if [ -z "$rollback_to" ]; then
      # shellcheck disable=SC2016
      log error "no profile version older than the current \`$current_gen\` exists"
      exit
    fi

  else
    if ! puressh "$target_host" ls /nix/var/nix/profiles \
      | grep -oP '(?<=system-)'"$rollback_to"'(?=-link)' > /dev/null
    then
      # shellcheck disable=SC2016
      log error 'no profile version \`$rollback_to\` exists'
      exit
    fi
  fi

  puressh "$target_host" <<EOF
    sudo nix profile rollback --profile /nix/var/nix/profiles/system --to '$rollback_to'
    sleep 1
    sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch
EOF
fi

if [ "${server_history+x}" ]; then
  puressh "$target_host" nix profile history --profile /nix/var/nix/profiles/system
  exit 0
fi

if [ "${push_deploy+x}" ]; then
  if [ "${via_hetzner+x}" ]; then
    # ------------------------------------------------------------------ #
    # push --via-hetzner                                                   #
    # Spin up an ephemeral Hetzner Cloud server, use it as --build-host,  #
    # then destroy it.                                                     #
    # ------------------------------------------------------------------ #

    # Resolve token: --hcloud-token arg takes precedence over env
    : "${hcloud_token:=${HCLOUD_TOKEN:-}}"
    if [ -z "$hcloud_token" ]; then
      log error "--hcloud-token not set and HCLOUD_TOKEN env is empty"
      exit 3
    fi
    export HCLOUD_TOKEN="$hcloud_token"

    # Defaults
    : "${builder_type:=cx52}"
    : "${builder_location:=nbg1}"

    # Resolve builder flake ref from current git rev so the builder
    # bootstraps the exact same commit that is being deployed
    if [ -z "${builder_flake:-}" ]; then
      git_rev=$(git rev-parse HEAD 2>/dev/null || true)
      if [ -z "$git_rev" ]; then
        log error "cannot resolve git HEAD -- run from the repo or pass --builder-flake"
        exit 3
      fi
      # shellcheck disable=SC2016
      builder_flake="github:hectic-lab/util.nix/${git_rev}#hetzner-builder|x86_64-linux"
    fi

    BUILDER_NAME="hetzner-builder-$$"

    # Private key for the hetzner-builder NixOS config.
    # The matching public key is hardcoded in nixos/system/hetzner-builder/hetzner-builder.nix.
    # Default path: ~/.ssh/hetzner-builder  (override with --builder-ssh-key)
    # Generate once with: ssh-keygen -t ed25519 -f ~/.ssh/hetzner-builder -C hetzner-builder
    : "${builder_ssh_key:=${HOME}/.ssh/hetzner-builder}"
    if [ ! -f "$builder_ssh_key" ]; then
      log error "builder ssh private key not found at \`${builder_ssh_key}\`"
      log error "generate it with: ssh-keygen -t ed25519 -f ~/.ssh/hetzner-builder -C hetzner-builder"
      log error "then add the public key to nixos/system/hetzner-builder/hetzner-builder.nix and commit"
      exit 3
    fi
    builder_pubkey=$(ssh-keygen -y -f "$builder_ssh_key")

    # --- Hetzner resource IDs to clean up ---
    HCLOUD_KEY_ID=""
    SERVER_ID=""
    SERVER_IP=""

    hetzner_cleanup() {
      if [ -n "$SERVER_ID" ]; then
        log info "deleting hetzner server ${SERVER_ID}..."
        hcloud server delete "$SERVER_ID" || true
      fi
      if [ -n "$HCLOUD_KEY_ID" ]; then
        log info "deleting hetzner ssh-key ${HCLOUD_KEY_ID}..."
        hcloud ssh-key delete "$HCLOUD_KEY_ID" || true
      fi
      if [ -n "${ssh_config_dir:-}" ]; then
        rm -rf "$ssh_config_dir"
      fi
    }
    trap hetzner_cleanup EXIT INT TERM

    # 1. Register the builder SSH public key in Hetzner
    log info "registering builder ssh key in hetzner..."
    HCLOUD_KEY_ID=$(hcloud ssh-key create \
      --name "$BUILDER_NAME" \
      --public-key "$builder_pubkey" \
      --output json \
      | grep -oP '(?<="id":)\d+' | head -1)

    # 2. Create the builder server
    log info "creating hetzner builder server (type=${builder_type}, location=${builder_location})..."
    server_output=$(hcloud server create \
      --name "$BUILDER_NAME" \
      --type "$builder_type" \
      --location "$builder_location" \
      --image "ubuntu-24.04" \
      --ssh-key "$HCLOUD_KEY_ID" \
      --output json)

    SERVER_ID=$(printf '%s' "$server_output" | grep -oP '(?<="id":)\d+' | head -1)
    SERVER_IP=$(printf '%s' "$server_output" \
      | grep -oP '"ip"\s*:\s*"\K[^"]+' | head -1)

    log info "server created: id=${SERVER_ID} ip=${SERVER_IP}"

    # 3. Wait for the rescue/ubuntu SSH to come up
    wait_for_ssh "root@${SERVER_IP}"

    # 4. Bootstrap NixOS via nixos-anywhere
    log info "bootstrapping nixos on builder (flake=${builder_flake})..."
    nixos-anywhere \
      --flake "$builder_flake" \
      --target-host "root@${SERVER_IP}" \
      -i "$builder_ssh_key"

    # 5. Wait for NixOS SSH after reboot
    wait_for_ssh "root@${SERVER_IP}"

    # 6. Run nixos-rebuild with the hetzner server as --build-host.
    #    All other args ($@) pass through unchanged -- flake, target-host, etc.
    log info "running nixos-rebuild switch via hetzner builder ${SERVER_IP}..."
    # Write a temporary SSH config so the builder host uses the builder key
    # while the target host (neuro) continues to use the default SSH identity.
    ssh_config_dir=$(mktemp -d)
    cat > "${ssh_config_dir}/config" <<SSHCFG
Host ${SERVER_IP}
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  IdentityFile ${builder_ssh_key}
  IdentitiesOnly yes
SSHCFG
    NIX_SSHOPTS="-F ${ssh_config_dir}/config"
    export NIX_SSHOPTS
    # shellcheck disable=SC2068
    nixos-rebuild switch \
      --build-host "root@${SERVER_IP}" \
      $@
    rm -rf "$ssh_config_dir"

    # 7. Cleanup fires via trap on EXIT

  elif [ "${server_init+x}" ]; then
    if [ "$is_target_host_nixos" -eq 1 ]; then
      log warn 'target host already is nixos, are you really want to reinstall nixos?'
      printf 'This may delete all data [y/N]\n'
      read -r CONTINUE
      if [ "$CONTINUE" != "y" ]; then
        exit 0
      fi
    fi

    # shellcheck disable=SC2068
    nixos-anywhere -- $@ # --flake .#x86_64-linux --target-host proxydoe

    wait_for_ssh "$target_host"

    server_public_age_key=$(puressh "$target_host" cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age)

    # shellcheck disable=SC2016
    log info "server's public age key is \`$server_public_age_key\` use it in sops file and run regular deploys"
  else
    if [ "$is_target_host_nixos" -ne 1 ]; then
      log error 'remote system not nixos'
      exit 1
    fi

    # shellcheck disable=SC2068
    nixos-rebuild switch $@ # --flake .#x86_64-linux --target-host proxydoe
  fi
fi
