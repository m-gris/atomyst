#!/usr/bin/env bash
# Run tree-sitter query tests and compare to expected output
set -euo pipefail

cd "$(dirname "$0")/../.."

PASS=0
FAIL=0

for test_dir in test/tree_sitter_queries/*/; do
    test_name=$(basename "$test_dir")
    # Remove trailing slash for clean paths
    test_dir="${test_dir%/}"
    query_file="$test_dir/query.scm"
    input_file="$test_dir/input.py"
    expected_file="$test_dir/expected.txt"

    if [[ ! -f "$query_file" || ! -f "$input_file" || ! -f "$expected_file" ]]; then
        continue
    fi

    actual=$(tree-sitter query --lib-path python.dylib --lang-name python "$query_file" "$input_file" 2>&1 || true)
    expected=$(cat "$expected_file")

    if [[ "$actual" == "$expected" ]]; then
        echo "✓ $test_name"
        PASS=$((PASS + 1))
    else
        echo "✗ $test_name"
        echo "  Expected:"
        echo "$expected" | sed 's/^/    /'
        echo "  Actual:"
        echo "$actual" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
    fi
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
