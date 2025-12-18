#!/bin/dash

HECTIC_NAMESPACE=test-help-and-version

### CASE 1: Help with no arguments
log notice "test case: ${WHITE}help with no arguments"

output=$(migrator 2>&1)
if ! printf '%s' "$output" | grep -q "migrator - Database Migration Tool"; then
  log error "test failed: ${WHITE}no help output when no arguments"
  exit 1
fi

### CASE 2: Explicit help command
log notice "test case: ${WHITE}explicit help command"

if ! migrator help | grep -q "USAGE:"; then
  log error "test failed: ${WHITE}help command doesn't work"
  exit 1
fi

### CASE 3: --help flag
log notice "test case: ${WHITE}--help flag"

if ! migrator --help | grep -q "COMMANDS:"; then
  log error "test failed: ${WHITE}--help flag doesn't work"
  exit 1
fi

### CASE 4: -h flag
log notice "test case: ${WHITE}-h flag"

if ! migrator -h | grep -q "EXAMPLES:"; then
  log error "test failed: ${WHITE}-h flag doesn't work"
  exit 1
fi

### CASE 5: --version flag
log notice "test case: ${WHITE}--version flag"

version_output=$(migrator --version)
if ! printf '%s' "$version_output" | grep -q "migrator version"; then
  log error "test failed: ${WHITE}--version doesn't show version"
  exit 1
fi

### CASE 6: -V flag
log notice "test case: ${WHITE}-V flag"

if ! migrator -V | grep -q "0.0.1"; then
  log error "test failed: ${WHITE}-V flag doesn't show version"
  exit 1
fi

### CASE 7: Help message contains database support info
log notice "test case: ${WHITE}help shows database support"

help_output=$(migrator help)
if ! printf '%s' "$help_output" | grep -q "PostgreSQL"; then
  log error "test failed: ${WHITE}help doesn't mention PostgreSQL"
  exit 1
fi

if ! printf '%s' "$help_output" | grep -q "SQLite"; then
  log error "test failed: ${WHITE}help doesn't mention SQLite"
  exit 1
fi

### CASE 8: Help mentions key commands
log notice "test case: ${WHITE}help shows all commands"

for cmd in init migrate create list fetch; do
  if ! printf '%s' "$help_output" | grep -qi "$cmd"; then
    log error "test failed: ${WHITE}help doesn't mention $cmd command"
    exit 1
  fi
done

log notice "test passed"

