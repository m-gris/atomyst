#!/usr/bin/env bash
# Fixture test: compare OCaml atomyst output to expected/ directories
set -euo pipefail

cd "$(dirname "$0")/.."

PASS=0
FAIL=0
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

test_fixture() {
    local fixture="$1"
    local name=$(basename "$fixture")
    local expected_dir="$fixture/expected"
    local output_dir="$TMPDIR/$name"

    # Skip if no expected/ directory
    if [[ ! -d "$expected_dir" ]]; then
        return
    fi

    # Run atomyst
    eval $(opam env) && dune exec atomyst -- "$fixture/input.py" -o "$output_dir" 2>/dev/null

    # Compare output to expected
    if diff -rq "$expected_dir" "$output_dir" >/dev/null 2>&1; then
        echo "✓ $name"
        PASS=$((PASS + 1))
    else
        echo "✗ $name"
        diff -r "$expected_dir" "$output_dir" 2>&1 | head -10 | sed 's/^/  /'
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Fixture Tests ==="
for fixture in test/fixtures/*/; do
    test_fixture "${fixture%/}"
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
