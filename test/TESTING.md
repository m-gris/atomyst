# Testing Strategy

Atomyst uses **fixture-based testing** with before/after filesystem snapshots.

## Philosophy

Following FP principles:
- **Pure functions** tested with simple assertions, no mocks
- **File I/O** tested via fixtures (expected input → expected output)
- **Golden tests**: compare actual output against committed expected output

## Directory Structure

```
test/
├── TESTING.md              # This file
├── fixture_test.sh         # Fixture-based test runner
├── fixtures/
│   ├── 01_simple_class/
│   │   ├── input.py        # Source file to atomize
│   │   └── expected/       # Expected output directory
│   │       ├── __init__.py
│   │       └── person.py
│   ├── 02_multiple_classes/
│   │   ├── input.py
│   │   └── expected/
│   ├── 03_decorators/
│   │   ├── input.py
│   │   └── expected/
│   └── ...
├── ocaml/                  # OCaml unit tests (dune test)
└── tree_sitter_queries/    # Tree-sitter query tests
```

## Test Categories

### 1. Name Conversion (`to_snake_case`)

| Input | Expected Output |
|-------|-----------------|
| `MyClass` | `my_class` |
| `HTTPServer` | `http_server` |
| `XMLParser` | `xml_parser` |
| `getHTTPResponse` | `get_http_response` |
| `already_snake` | `already_snake` |
| `A` | `a` |
| `ABCDef` | `abc_def` |

### 2. Definition Extraction

| Scenario | What to Test |
|----------|--------------|
| Single class | Basic extraction works |
| Multiple classes | All extracted, order preserved |
| Functions | Standalone functions extracted |
| Async functions | `async def` handled |
| Mixed (classes + functions) | Both types extracted |
| Decorated definitions | Decorators included in line range |
| Multiple decorators | All decorators captured |
| Nested classes | NOT extracted (only top-level) |
| Class methods | NOT extracted (belong to class) |

### 3. Comment Handling

| Scenario | What to Test |
|----------|--------------|
| Comment directly above class | Included with class |
| Blank line then comment | Comment stays orphaned (by design) |
| Docstrings | Included (they're inside the definition) |
| Inline comments | Preserved (we slice lines) |

### 4. Import Handling

| Scenario | What to Test |
|----------|--------------|
| Simple imports | Copied to all output files |
| Multi-line imports | Parenthesized imports handled |
| `TYPE_CHECKING` block | Copied as-is |
| Relative imports | Preserved |

### 5. Edge Cases

| Scenario | What to Test |
|----------|--------------|
| Empty file | No definitions found, graceful exit |
| File with only imports | No definitions found |
| Module-level constants | Not extracted (only classes/functions) |
| `TypeVar` declarations | Not extracted |
| `__all__` declaration | Not extracted |
| Forward references | Files created, import errors expected (fixed by formatter) |

### 6. Filesystem Output

| Scenario | What to Test |
|----------|--------------|
| Output directory created | `mkdir -p` behavior |
| Files have correct names | snake_case conversion |
| `__init__.py` generated | Re-exports all definitions |
| `__all__` in init | Lists all exported names |

## Running Tests

```bash
# All tests (OCaml unit tests + tree-sitter queries)
just test

# Fixture tests (compare output to expected/)
just test-fixtures

# Tree-sitter query tests only
just test-queries

# OCaml unit tests only
just test-ocaml
```

## Adding a New Test

1. Create directory: `test/fixtures/NN_descriptive_name/`
2. Add `input.py` with source to atomize
3. Run atomyst to generate output
4. Review output manually
5. Move to `expected/` if correct
6. Commit fixture

## Golden Test Pattern

The fixture tests (`test/fixture_test.sh`) follow this pattern:

```bash
# For each fixture with an expected/ directory:
# 1. Run atomyst on input.py, output to temp dir
# 2. Compare temp dir contents with expected/ using diff -r
# 3. Pass if identical, fail with diff output otherwise
```

## Invariants to Assert

For any valid atomization:

1. **Definition count preserved**: `len(extracted) == count_top_level_defs(input)`
2. **All names appear in __init__.py**: Every extracted name is re-exported
3. **No content lost**: Union of all output files covers all definitions
4. **Line ranges don't overlap**: Each definition's range is disjoint
5. **Output compiles**: `python -m py_compile <file>` succeeds (syntax check)
