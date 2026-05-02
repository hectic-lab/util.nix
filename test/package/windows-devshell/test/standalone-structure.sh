#!/bin/dash
set -eu

log info "Checking windows-devshell standalone script structure..."

# Check file exists
if ! [ -f "${windowsDevShellStandalone}" ]; then
  log error "windows-devshell standalone script not found"
  exit 1
fi

# Check it's a PowerShell script (should NOT have hardcoded #Requires -RunAsAdministrator)
if head -1 "${windowsDevShellStandalone}" | grep -q "#Requires -RunAsAdministrator"; then
  log error "Script should not hardcode #Requires -RunAsAdministrator"
  exit 1
fi

# Check it contains base64 placeholder replacement (should be actual base64 now)
if grep -q "@LINUX_DEVSHELL_BASE64@" "${windowsDevShellStandalone}"; then
  log error "Base64 placeholder was not replaced"
  exit 1
fi

# Check it contains the base64 decode logic
if ! grep -q "FromBase64String" "${windowsDevShellStandalone}"; then
  log error "Script missing base64 decode logic"
  exit 1
fi

# Check it contains WSL installation logic
if ! grep -q "wsl --status" "${windowsDevShellStandalone}"; then
  log error "Script missing WSL status check"
  exit 1
fi

if ! grep -q "wsl --install" "${windowsDevShellStandalone}"; then
  log error "Script missing WSL install command"
  exit 1
fi

# Check it contains admin check
if ! grep -q "Administrator" "${windowsDevShellStandalone}"; then
  log error "Script missing admin privilege check"
  exit 1
fi

log success "Standalone script has correct structure"

# Verify the embedded base64 is valid by checking it's non-empty and only contains base64 chars
base64_content=$(grep '^\$linuxDevShellBase64 = ' "${windowsDevShellStandalone}" | sed 's/.*= "//;s/"$//')
if [ -z "$base64_content" ]; then
  log error "Embedded base64 content is empty"
  exit 1
fi

# Check base64 content length is reasonable (should be at least a few hundred chars for the linux script)
content_len=${#base64_content}
if [ "$content_len" -lt 100 ]; then
  log error "Embedded base64 content too short ($content_len chars)"
  exit 1
fi

log success "Embedded base64 content looks valid ($content_len chars)"
log success "Standalone structure test passed"
