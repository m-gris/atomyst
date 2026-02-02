#!/usr/bin/env bash
# Integration test: --prefix-kind + lint
set -euo pipefail

cd "$(dirname "$0")/.."

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

PASS=0
FAIL=0

pass() { echo "✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "✗ $1"; FAIL=$((FAIL + 1)); }

# Test 1: atomize with --prefix-kind, then lint should pass
echo "=== Integration: --prefix-kind + lint ==="

eval $(opam env)
dune exec atomyst -- atomize test/fixtures/17_prefix_kind/input.py \
    -o "$TMPDIR/prefixed" --prefix-kind --keep-original >/dev/null

if dune exec atomyst -- lint "$TMPDIR/prefixed" >/dev/null 2>&1; then
    pass "lint passes on correctly prefixed output"
else
    fail "lint should pass on correctly prefixed output"
fi

# Test 2: create a mismatched file, lint should fail
echo 'def not_a_class():
    pass' > "$TMPDIR/prefixed/class_wrong.py"

if dune exec atomyst -- lint "$TMPDIR/prefixed" >/dev/null 2>&1; then
    fail "lint should fail on mismatched prefix"
else
    pass "lint fails on mismatched prefix"
fi

# Test 3: atomize without --prefix-kind, lint should pass (no prefixes to check)
dune exec atomyst -- atomize test/fixtures/01_simple_class/input.py \
    -o "$TMPDIR/unprefixed" --keep-original >/dev/null

if dune exec atomyst -- lint "$TMPDIR/unprefixed" >/dev/null 2>&1; then
    pass "lint passes on unprefixed output"
else
    fail "lint should pass on unprefixed output (no prefix constraints)"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
