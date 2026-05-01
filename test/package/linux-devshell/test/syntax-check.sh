#!/bin/dash
set -eu

log notice "test case: ${WHITE}syntax check"

log info "Checking standard package script syntax..."
dash -n "${linuxDevShell}/bin/linux-devshell" || {
  log error "Standard package script has syntax errors"
  exit 1
}
log success "Standard package script syntax is valid"

log info "Checking standalone script syntax..."
dash -n "${linuxDevShellStandalone}" || {
  log error "Standalone script has syntax errors"
  exit 1
}
log success "Standalone script syntax is valid"

log info "Checking script contains Nix detection logic..."
grep -q 'command -v nix' "${linuxDevShellStandalone}" || {
  log error "Standalone script missing Nix detection"
  exit 1
}
log success "Script contains Nix detection logic"

log notice "test passed"
