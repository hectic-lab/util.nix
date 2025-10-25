#!/bin/dash

# requirements: ssh-to-age nixos-anywhere

# ssh proxydoe 'cat /etc/os-release 2>/dev/null || echo "no /etc/os-release"' | grep '^NAME=NixOS$'
# NAME=NixOS

# ssh that not saves the host in ~/.ssh/know_hosts
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

saved_args="$*"

# parse command and independent params
while [ $# -gt 0 ]; do
  case $1 in
    push)
      if [ ${founded_command+x} ]; then
        # shellcheck disable=SC2016
	printf 'ambiguous subcommand `%s` and `%s`\n' "$1" "$founded_command"
	exit 1
      fi

      push_deploy=1
      founded_command="$1"
      shift
      ;;
    rollback)
      if [ ${founded_command+x} ]; then
        # shellcheck disable=SC2016
	printf 'ambiguous subcommand `%s` and `%s`\n' "$1" "$founded_command"
	exit 1
      fi

      rollback_deploy=1
      founded_command="$1"
      shift
      ;;
    history)
      if [ ${founded_command+x} ]; then
        # shellcheck disable=SC2016
	printf 'ambiguous subcommand `%s` and `%s`\n' "$1" "$founded_command"
	exit 1
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
        printf 'illegal %s\n' "$1"
      fi 
      shift
      ;;
    --to)
      if [ ${rollback_deploy+x} ]; then
	rollback_to="$2"
      else
        printf 'illegal %s\n' "$1"
      fi
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
        printf 'you specified 2 ambiguous target hosts %s and %s\n' "$target_host" "$2"
	exit 1
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
  printf '%s not set, but required\n' '--target-host'
  exit 1
fi

if puressh "$target_host" 'cat /etc/os-release 2>/dev/null || echo "no /etc/os-release"' \
  | grep -q '^NAME=NixOS$'
then
  is_target_host_nixos=1
else
  is_target_host_nixos=0
fi

#??
#ssh "$target_host" 'grep -q "^NAME=NixOS$" /etc/os-release 2>/dev/null'
#is_target_host_nixos=$?

if [ "${rollback_deploy+x}" ]; then
  if ! [ "${rollback_to+x}" ]; then
    current_gen=$(puressh "$target_host" readlink /nix/var/nix/profiles/system \
      | sed -n 's/^system-\([0-9]\+\)-link$/\1/p')

    rollback_to=$(puressh "$target_host" ls /nix/var/nix/profiles | find_older_gen "$current_gen")

    if [ -z "$rollback_to" ]; then
      # shellcheck disable=SC2016
      printf 'no profile version older than the current `%s` exists\n' "$current_gen"
      exit
    fi

  else
    if ! puressh "$target_host" ls /nix/var/nix/profiles \
      | grep -oP '(?<=system-)'"$rollback_to"'(?=-link)' > /dev/null
    then
      # shellcheck disable=SC2016
      printf 'no profile version `%s` exists\n' "$rollback_to"
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
  if [ "${server_init+x}" ]; then
    if [ "$is_target_host_nixos" -eq 1 ]; then
      printf 'target host already is nixos, are you realy want to reinstall nixos?\nThis may delete all data [y/N]\n' 
      read -r CONTINUE
      if [ "$CONTINUE" != "y" ]; then
        exit 0
      fi
    fi
  
    # shellcheck disable=SC2068
    nixos-anywhere -- $@ # --flake .#x86_64-linux --target-host proxydoe
    
    server_public_age_key=$(puressh "$target_host" cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age)
  
    # shellcheck disable=SC2016
    printf 'server'"'"'s public age key is `%s` use it in sops file and run regular deploys\n' "$server_public_age_key"
  else
    if [ "$is_target_host_nixos" -ne 1 ]; then
      printf 'remote system not nixos\n'
      exit 1 
    fi
  
    # shellcheck disable=SC2068
    nixos-rebuild switch $@ # --flake .#x86_64-linux --target-host proxydoe
  fi
fi
