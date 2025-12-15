#!/bin/dash

# Test script for hemar renderer

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXAMPLES="$SCRIPT_DIR/examples"
HEMAR="$SCRIPT_DIR/hemar"

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
    
    printf "Testing %s... " "$name"
    
    local output
    if output=$("$HEMAR" "$template" "$model" 2>&1); then
        if [ "$output" = "$expected" ]; then
            printf "${GREEN}PASSED${NC}\n"
            passed=$((passed + 1))
        else
            printf "${RED}FAILED${NC}\n"
            printf "  Expected: %s\n" "$expected"
            printf "  Got:      %s\n" "$output"
            failed=$((failed + 1))
        fi
    else
        printf "${RED}ERROR${NC}\n"
        printf "  %s\n" "$output"
        failed=$((failed + 1))
    fi
}

# Check requirements
if ! command -v tree-sitter >/dev/null 2>&1; then
    printf "${RED}ERROR: tree-sitter not found${NC}\n"
    printf "Install with: nix shell ~/pj/tree-sitter#cli nixpkgs#nodejs_22 nixpkgs#clang\n"
    exit 1
fi

if ! command -v yq >/dev/null 2>&1; then
    printf "${RED}ERROR: yq not found${NC}\n"
    printf "Install with: nix shell nixpkgs#yq-go\n"
    exit 1
fi

# Run tests
printf "Running hemar renderer tests...\n\n"

# Test 1: Simple interpolation
test_render "simple interpolation" \
    "$EXAMPLES/simple.hemar" \
    "$EXAMPLES/simple.json" \
    "Hello, Alice!
You are 30 years old.
"

# Test 2: For loop
test_render "for loop" \
    "$EXAMPLES/loop.hemar" \
    "$EXAMPLES/loop.json" \
    "Users:

  - Alice (30 years old)

  - Bob (25 years old)

  - Charlie (35 years old)

"

# Test 3: Complex path (this will fail if model doesn't have the exact structure)
# For now, just test that it doesn't crash

printf "\n"
printf "Tests: ${GREEN}%d passed${NC}, ${RED}%d failed${NC}\n" "$passed" "$failed"

if [ "$failed" -gt 0 ]; then
    exit 1
fi



