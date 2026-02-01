#!/usr/bin/env bash
# Test: original file removal behavior after atomization
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

PASS=0
FAIL=0
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Build atomyst
eval $(opam env) && dune build

# Run atomyst from project root with full paths
run_atomyst() {
    (cd "$PROJECT_ROOT" && dune exec atomyst -- "$@")
}

pass() {
    echo "✓ $1"
    PASS=$((PASS + 1))
}

fail() {
    echo "✗ $1"
    echo "  $2"
    FAIL=$((FAIL + 1))
}

# Test 1: git-tracked clean file → removed by default
test_default_removes_clean_tracked() {
    local dir="$TMPDIR/test1"
    mkdir -p "$dir"
    (
        cd "$dir"
        git init -q
        printf 'class Foo:\n    pass\n' > test.py
        git add test.py
        git commit -q -m "initial"
    )

    run_atomyst "$dir/test.py" -o "$dir/output" >/dev/null 2>&1

    if [[ ! -f "$dir/test.py" ]]; then
        pass "default removes clean tracked file"
    else
        fail "default removes clean tracked file" "file still exists"
    fi
}

# Test 2: --keep-original preserves file
test_keep_original_flag() {
    local dir="$TMPDIR/test2"
    mkdir -p "$dir"
    (
        cd "$dir"
        git init -q
        printf 'class Foo:\n    pass\n' > test.py
        git add test.py
        git commit -q -m "initial"
    )

    run_atomyst "$dir/test.py" -o "$dir/output" --keep-original >/dev/null 2>&1

    if [[ -f "$dir/test.py" ]]; then
        pass "--keep-original preserves file"
    else
        fail "--keep-original preserves file" "file was removed"
    fi
}

# Test 3: untracked file → kept
test_untracked_kept() {
    local dir="$TMPDIR/test3"
    mkdir -p "$dir"
    (
        cd "$dir"
        git init -q
        printf 'class Foo:\n    pass\n' > test.py
        # Don't add to git
    )

    run_atomyst "$dir/test.py" -o "$dir/output" >/dev/null 2>&1

    if [[ -f "$dir/test.py" ]]; then
        pass "untracked file is kept"
    else
        fail "untracked file is kept" "file was removed"
    fi
}

# Test 4: file with uncommitted changes → kept
test_uncommitted_changes_kept() {
    local dir="$TMPDIR/test4"
    mkdir -p "$dir"
    (
        cd "$dir"
        git init -q
        printf 'class Foo:\n    pass\n' > test.py
        git add test.py
        git commit -q -m "initial"
        echo '# modified' >> test.py
    )

    run_atomyst "$dir/test.py" -o "$dir/output" >/dev/null 2>&1

    if [[ -f "$dir/test.py" ]]; then
        pass "file with uncommitted changes is kept"
    else
        fail "file with uncommitted changes is kept" "file was removed"
    fi
}

# Test 5: file not in git repo → kept
test_not_in_repo_kept() {
    local dir="$TMPDIR/test5"
    mkdir -p "$dir"
    printf 'class Foo:\n    pass\n' > "$dir/test.py"
    # No git init

    run_atomyst "$dir/test.py" -o "$dir/output" >/dev/null 2>&1

    if [[ -f "$dir/test.py" ]]; then
        pass "file not in git repo is kept"
    else
        fail "file not in git repo is kept" "file was removed"
    fi
}

# Test 6: dry-run never removes
test_dry_run_never_removes() {
    local dir="$TMPDIR/test6"
    mkdir -p "$dir"
    (
        cd "$dir"
        git init -q
        printf 'class Foo:\n    pass\n' > test.py
        git add test.py
        git commit -q -m "initial"
    )

    run_atomyst "$dir/test.py" -o "$dir/output" --dry-run >/dev/null 2>&1

    if [[ -f "$dir/test.py" ]]; then
        pass "dry-run never removes file"
    else
        fail "dry-run never removes file" "file was removed"
    fi
}

echo "=== Original File Removal Tests ==="
test_default_removes_clean_tracked
test_keep_original_flag
test_untracked_kept
test_uncommitted_changes_kept
test_not_in_repo_kept
test_dry_run_never_removes

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
