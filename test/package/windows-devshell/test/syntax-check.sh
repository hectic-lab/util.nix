#!/bin/dash
set -eu

log info "Checking PowerShell script syntax (basic validation)..."

# Since we can't run PowerShell in Nix, we do basic structural validation

# Check for balanced braces
open_braces=$(grep -o '{' "${windowsDevShellStandalone}" | wc -l)
close_braces=$(grep -o '}' "${windowsDevShellStandalone}" | wc -l)
if [ "$open_braces" -ne "$close_braces" ]; then
  log error "Unbalanced braces: $open_braces open, $close_braces close"
  exit 1
fi

# Check for balanced parentheses
open_parens=$(grep -o '(' "${windowsDevShellStandalone}" | wc -l)
close_parens=$(grep -o ')' "${windowsDevShellStandalone}" | wc -l)
if [ "$open_parens" -ne "$close_parens" ]; then
  log error "Unbalanced parentheses: $open_parens open, $close_parens close"
  exit 1
fi

# Check no obvious syntax errors (unclosed strings)
# Count quotes - should be even
quotes=$(grep -o '"' "${windowsDevShellStandalone}" | wc -l)
if [ $((quotes % 2)) -ne 0 ]; then
  log error "Unbalanced quotes: $quotes total (should be even)"
  exit 1
fi

# Check script has reasonable length
lines=$(wc -l < "${windowsDevShellStandalone}")
if [ "$lines" -lt 50 ]; then
  log error "Script too short ($lines lines)"
  exit 1
fi

log success "PowerShell script passes basic structural validation"
log success "Script is $lines lines, braces/parentheses/quotes balanced"
