#!/bin/dash

init_plex() {
  local backend
  backend=${1:?}

  case "$backend" in
    env)
      . ${WORKSPACE}/src/plex/backend/env_var.sh
      ;;
    file)
      . ${WORKSPACE}/src/plex/backend/file.sh
      ;;
    yq-go)
      . ${WORKSPACE}/src/plex/backend/yq-go.sh
      ;;
    *)
      exit 1
      ;;
  esac
}
