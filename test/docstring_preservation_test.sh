#!/usr/bin/env bash
# Test: module docstring preservation in __init__.py
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

# Test 1: Single-line docstring is preserved
test_single_line_docstring() {
    local dir="$TMPDIR/test1"
    mkdir -p "$dir"
    printf '"""My awesome module."""\n\nclass Foo:\n    pass\n' > "$dir/test.py"

    run_atomyst "$dir/test.py" -o "$dir/output" --keep-original >/dev/null 2>&1

    if grep -q "My awesome module" "$dir/output/__init__.py"; then
        pass "single-line docstring preserved"
    else
        fail "single-line docstring preserved" "docstring not found in __init__.py"
    fi
}

# Test 2: Multi-line docstring is preserved
test_multiline_docstring() {
    local dir="$TMPDIR/test2"
    mkdir -p "$dir"
    printf '"""My module.\n\nThis does awesome things.\n"""\n\nclass Foo:\n    pass\n' > "$dir/test.py"

    run_atomyst "$dir/test.py" -o "$dir/output" --keep-original >/dev/null 2>&1

    if grep -q "awesome things" "$dir/output/__init__.py"; then
        pass "multi-line docstring preserved"
    else
        fail "multi-line docstring preserved" "docstring content not found"
    fi
}

# Test 3: Atomization metadata is added
test_atomization_metadata() {
    local dir="$TMPDIR/test3"
    mkdir -p "$dir"
    printf '"""Original docstring."""\n\nclass Foo:\n    pass\n' > "$dir/test.py"

    run_atomyst "$dir/test.py" -o "$dir/output" --keep-original >/dev/null 2>&1

    if grep -q "atomyst" "$dir/output/__init__.py" && \
       grep -q "Source: test.py" "$dir/output/__init__.py"; then
        pass "atomization metadata present"
    else
        fail "atomization metadata present" "metadata not found in __init__.py"
    fi
}

# Test 3b: Manifesto is included
test_manifesto_present() {
    local dir="$TMPDIR/test3b"
    mkdir -p "$dir"
    printf '"""Original docstring."""\n\nclass Foo:\n    pass\n' > "$dir/test.py"

    run_atomyst "$dir/test.py" -o "$dir/output" --keep-original >/dev/null 2>&1

    if grep -q "One definition per file" "$dir/output/__init__.py" && \
       grep -q "tree src" "$dir/output/__init__.py"; then
        pass "manifesto present in __init__.py"
    else
        fail "manifesto present in __init__.py" "manifesto text not found"
    fi
}

# Test 3c: Tool URL is included
test_tool_url_present() {
    local dir="$TMPDIR/test3c"
    mkdir -p "$dir"
    printf '"""Original docstring."""\n\nclass Foo:\n    pass\n' > "$dir/test.py"

    run_atomyst "$dir/test.py" -o "$dir/output" --keep-original >/dev/null 2>&1

    if grep -q "github.com/m-gris/atomyst" "$dir/output/__init__.py"; then
        pass "tool URL present"
    else
        fail "tool URL present" "URL not found in __init__.py"
    fi
}

# Test 4: No docstring generates metadata-only docstring
test_no_docstring_generates_metadata() {
    local dir="$TMPDIR/test4"
    mkdir -p "$dir"
    printf 'class Foo:\n    pass\n' > "$dir/test.py"

    run_atomyst "$dir/test.py" -o "$dir/output" --keep-original >/dev/null 2>&1

    if grep -q "Source: test.py" "$dir/output/__init__.py" && \
       grep -q "One definition per file" "$dir/output/__init__.py"; then
        pass "no docstring -> metadata docstring generated"
    else
        fail "no docstring -> metadata docstring generated" "generated docstring not found"
    fi
}

# Test 5: Imports are still present
test_imports_present() {
    local dir="$TMPDIR/test5"
    mkdir -p "$dir"
    printf '"""My module."""\n\nclass Foo:\n    pass\n\nclass Bar:\n    pass\n' > "$dir/test.py"

    run_atomyst "$dir/test.py" -o "$dir/output" --keep-original >/dev/null 2>&1

    if grep -q "from .foo import Foo" "$dir/output/__init__.py" && \
       grep -q "from .bar import Bar" "$dir/output/__init__.py"; then
        pass "imports present in __init__.py"
    else
        fail "imports present in __init__.py" "imports not found"
    fi
}

# Test 6: __all__ is present
test_all_present() {
    local dir="$TMPDIR/test6"
    mkdir -p "$dir"
    printf '"""My module."""\n\nclass Foo:\n    pass\n' > "$dir/test.py"

    run_atomyst "$dir/test.py" -o "$dir/output" --keep-original >/dev/null 2>&1

    if grep -q "__all__" "$dir/output/__init__.py" && \
       grep -q '"Foo"' "$dir/output/__init__.py"; then
        pass "__all__ present with definition"
    else
        fail "__all__ present with definition" "__all__ not found correctly"
    fi
}

echo "=== Docstring Preservation Tests ==="
test_single_line_docstring
test_multiline_docstring
test_atomization_metadata
test_manifesto_present
test_tool_url_present
test_no_docstring_generates_metadata
test_imports_present
test_all_present

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
