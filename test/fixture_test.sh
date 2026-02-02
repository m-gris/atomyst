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

    # Read extra options from options file if present
    local extra_opts=""
    if [[ -f "$fixture/options" ]]; then
        extra_opts=$(cat "$fixture/options")
    fi

    # Run atomyst (always keep original for tests)
    eval $(opam env) && dune exec atomyst -- atomize "$fixture/input.py" -o "$output_dir" --keep-original $extra_opts 2>/dev/null

    # Compare output to expected (ignoring timestamps)
    # Use diff with -I to ignore timestamp lines in __init__.py
    local diff_output
    diff_output=$(diff -r -I '^Source:.*|.*T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z' "$expected_dir" "$output_dir" 2>&1 || true)
    if [[ -z "$diff_output" ]]; then
        echo "✓ $name"
        PASS=$((PASS + 1))
    else
        echo "✗ $name"
        echo "$diff_output" | head -10 | sed 's/^/  /'
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
