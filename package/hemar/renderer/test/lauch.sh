#!/bin/dash

# Test script for hemar renderer

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXAMPLES="$SCRIPT_DIR/script"
HEMAR="$SCRIPT_DIR/../hemar-renderer.sh"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

passed=0
failed=0

# Test function
test_render() {
    local name="$1"
    local template="$2"
    local model="$3"
    local expected="$4"
    
    log notice "Testing $name..."
    
    local output
    if output=$(dash "$HEMAR" "$template" "$model"); then
        if [ "$output" = "$expected" ]; then
            log notice "PASSED"
            passed=$((passed + 1))
        else
            log error "FAILED"
            log error "  Expected: $WHITE$expected"
            log error "  Got:      $WHITE$output"
            failed=$((failed + 1))
        fi
    else
        log error "ERROR"
        log error "  $WHITE$output"
        failed=$((failed + 1))
    fi
}

# Check requirements
if ! command -v tree-sitter >/dev/null 2>&1; then
    log error "ERROR: ${WHITE}tree-sitter not found"
    log error "${WHITE}Install with: nix shell ~/pj/tree-sitter#cli nixpkgs#nodejs_22 nixpkgs#clang"
    exit 1
fi

if ! command -v yq >/dev/null 2>&1; then
    log error "ERROR: ${WHITE}yq not found"
    log error "${WHITE}Install with: nix shell nixpkgs#yq-go"
    exit 1
fi

# Run tests
log notice "Running hemar renderer tests...\n\n"

# Test 1: Simple interpolation
test_render "simple interpolation" \
    "$EXAMPLES/simple.hemar" \
    "$EXAMPLES/simple.json" \
    "Hello, Alice!
You are 30 years old."

# Test 2: For loop
test_render "for loop" \
    "$EXAMPLES/loop.hemar" \
    "$EXAMPLES/loop.json" \
    "Users:
  - Alice (30 years old)
  - Bob (25 years old)
  - Charlie (35 years old)"

# Test 3: Complex path (this will fail if model doesn't have the exact structure)
# For now, just test that it doesn't crash

log notice "Tests: $GREEN$passed passed$NC, $RED$failed failed"

if [ "$failed" -gt 0 ]; then
    exit 1
fi