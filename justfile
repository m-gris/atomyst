# Atomyst development recipes
# Run `just --list` to see available recipes

set shell := ["bash", "-euo", "pipefail", "-c"]

# Default recipe: build and test
default: build test

# Build the project
build:
    eval $(opam env) && dune build

# Run all tests (OCaml + fixtures + tree-sitter queries + integration)
test: test-ocaml test-fixtures test-queries test-integration

# Run prefix+lint integration test
test-integration:
    ./test/prefix_lint_test.sh

# Run OCaml tests
test-ocaml:
    eval $(opam env) && dune test

# Run OCaml tests with verbose output
test-ocaml-verbose:
    eval $(opam env) && dune runtest --force

# Run tree-sitter query tests
test-queries:
    ./test/tree_sitter_queries/run_tests.sh

# Run a tree-sitter query on a file
# Usage: just ts-query queries/definitions.scm test/fixtures/01_simple_class/input.py
ts-query query_file input_file:
    tree-sitter query --lib-path python.dylib --lang-name python "{{query_file}}" "{{input_file}}"

# Explore tree-sitter output for a Python file using the definitions query
ts-defs file:
    tree-sitter query --lib-path python.dylib --lang-name python queries/definitions.scm "{{file}}"

# Parse a Python file and dump the full AST (useful for query development)
ts-parse file:
    tree-sitter parse --lib-path python.dylib --lang-name python "{{file}}"

# Generate expected.txt for a query test case
# Usage: just ts-expected test/tree_sitter_queries/01_basic_definitions
ts-expected test_dir:
    tree-sitter query --lib-path python.dylib --lang-name python \
        "{{test_dir}}/query.scm" "{{test_dir}}/input.py" > "{{test_dir}}/expected.txt"

# Run OCaml atomyst CLI with arguments
# Usage: just run test/fixtures/01_simple_class/input.py --dry-run
# Usage: just run lint /path/to/atomized/dir
run *args:
    eval $(opam env) && dune exec atomyst -- {{args}}

# Atomize a file (shorthand for: just run atomize ...)
atomize *args:
    eval $(opam env) && dune exec atomyst -- atomize {{args}}

# Run fixture tests (compare output to expected/)
test-fixtures:
    ./test/fixture_test.sh

# Clean build artifacts
clean:
    dune clean

# Watch and rebuild on changes
watch:
    eval $(opam env) && dune build --watch

# Format OCaml code (if ocamlformat is installed)
fmt:
    eval $(opam env) && dune fmt 2>/dev/null || echo "ocamlformat not configured"

# Show beads status
beads:
    bd ready

# Compile and run an OCaml script (for debugging)
# Usage: just run-ml test/ocaml/debug_regex.ml
run-ml file:
    eval $(opam env) && ocamlfind ocamlopt -package re,re.pcre -linkpkg "{{file}}" -o /tmp/ocaml_debug && /tmp/ocaml_debug
