#!/bin/dash

# requirements: ssh-to-age nixos-anywhere
# jjjn

# ssh proxydoe 'cat /etc/os-release 2>/dev/null || echo "no /etc/os-release"' | grep '^NAME=NixOS$'
# NAME=NixOS

server_init=0

set -- "$@"

while [ $# -gt 0 ]; do
    case $1 in
	--init)
	  server_init=1
	  shift
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
	    # NOTE(yukkop):
	    # `saved_nix_args` fills only after "end of arguments"
            if [ "${saved_nix_args+x}" ]; then
                target_host=$2
                break
            fi
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# NOTE: restore original args
set -- "$saved_nix_args"

if ! [ ${target_host+x} ]; then
  printf '%s' '-- --target-host not set, but required'
  exit 1
fi

if ssh  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$target_host" 'cat /etc/os-release 2>/dev/null || echo "no /etc/os-release"' \
  | grep -q '^NAME=NixOS$'
then
  is_target_host_nixos=1
else
  is_target_host_nixos=0
fi

#??
#ssh "$target_host" 'grep -q "^NAME=NixOS$" /etc/os-release 2>/dev/null'
#is_target_host_nixos=$?

if [ "$server_init" -eq 1 ]; then
  if [ "$is_target_host_nixos" -eq 1 ]; then
    printf 'target host already is nixos, are you realy want to reinstall nixos?\nThis may delete all data [y/N]' 
    read -r CONTINUE
    if [ "$CONTINUE" != "y" ]; then
      exit 0
    fi
  fi

  # shellcheck disable=SC2068
  nixos-anywhere -- $@ # --flake .#x86_64-linux --target-host proxydoe
  
  server_public_age_key=$(ssh  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$target_host" cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age)

  # shellcheck disable=SC2016
  printf 'server'"'"'s public age key is `%s` use it in sops file and run regular deploys' "$server_public_age_key"
else
  if [ "$is_target_host_nixos" -ne 1 ]; then
    echo remote system not nixos
    exit 1 
  fi

  # shellcheck disable=SC2068
  nixos-rebuild switch $@ # --flake .#x86_64-linux --target-host proxydoe
fi
