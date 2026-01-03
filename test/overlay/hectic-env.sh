assert_eq() {
    expected=$1
    actual=$2
    name=$3

    if [ "$expected" != "$actual" ]; then
        printf 'FAIL: %s\nEXPECTED:\n%s\nGOT:\n%s\n' "$name" "$expected" "$actual" >&2
        exit 1
    fi
}

# Test 1: shebang, one include
printf '#!/bin/sh\necho target\n' > target1.sh
printf 'echo inc1\n' > inc1.sh

hectInclude inc1.sh target1.sh
out=$(cat target1.sh)
exp='#!/bin/sh
echo inc1
echo target'
assert_eq "$exp" "$out" "shebang + one include"

# Test 2: no shebang
printf 'echo target\n' > target2.sh
printf 'echo inc1\n' > inc1.sh

hectInclude inc1.sh target2.sh
out=$(cat target2.sh)
exp='echo inc1
echo target'
assert_eq "$exp" "$out" "no shebang"

# Test 3: shebang + multiple includes
printf '#!/bin/sh\necho target\n' > target3.sh
printf 'echo inc1\n' > inc1.sh
printf 'echo inc2\n' > inc2.sh

hectInclude inc1.sh inc2.sh target3.sh
out=$(cat target3.sh)
exp='#!/bin/sh
echo inc1
echo inc2
echo target'
assert_eq "$exp" "$out" "multiple includes"

# Test 4: minimal target
printf 'target\n' > target4.sh
printf 'inc\n' > inc1.sh

hectInclude inc1.sh target4.sh
out=$(cat target4.sh)
exp='inc
target'
assert_eq "$exp" "$out" "minimal target"

echo "ALL TESTS PASSED"
