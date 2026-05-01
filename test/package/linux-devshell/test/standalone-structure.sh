#!/bin/dash
set -eu

log notice "test case: ${WHITE}syntax check"

log info "Checking standard package binary exists..."
[ -x "${linuxDevShell}/bin/linux-devshell" ] || {
  log error "linux-devshell binary not found or not executable"
  exit 1
}
log success "Standard package binary exists"

log info "Checking standalone script exists..."
[ -x "${linuxDevShellStandalone}" ] || {
  log error "linux-devshell-standalone script not found or not executable"
  exit 1
}
log success "Standalone script exists"

log info "Checking standalone script has portable shebang..."
head -1 "${linuxDevShellStandalone}" | grep -q '^#!/bin/sh$' || {
  log error "Standalone script does not have #!/bin/sh shebang"
  exit 1
}
log success "Standalone script has portable shebang"

log info "Checking standalone script contains log helpers..."
grep -q 'log_info()' "${linuxDevShellStandalone}" || {
  log error "Standalone script missing log_info helper"
  exit 1
}
grep -q 'log_error()' "${linuxDevShellStandalone}" || {
  log error "Standalone script missing log_error helper"
  exit 1
}
log success "Standalone script contains log helpers"

log info "Checking standalone script contains main logic..."
grep -q 'detect_shell()' "${linuxDevShellStandalone}" || {
  log error "Standalone script missing detect_shell function"
  exit 1
}
grep -q 'install_nix()' "${linuxDevShellStandalone}" || {
  log error "Standalone script missing install_nix function"
  exit 1
}
log success "Standalone script contains main logic"

log notice "test passed"
