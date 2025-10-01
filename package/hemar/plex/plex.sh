#!/bin/dash

init_plex() {
  local backend
  backend=${1:?}

  case "$backend" in
    env)
      . ${WORKSPACE}/plex/backend/env_var.sh
      ;;
    file)
      . ${WORKSPACE}/plex/backend/file.sh
      ;;
    *)
      exit 1
      ;;
  esac
}
