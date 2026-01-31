# Tree-sitter Query Tests

This directory contains tests for tree-sitter Python queries used by atomyst.

## Running Tests

```bash
./run_tests.sh
```

## Query Output Format

tree-sitter query output looks like:
```
filename.py
  pattern: 0
    capture: class.def, start: (7, 0), end: (11, 12)
    capture: 0 - class.name, start: (7, 6), end: (7, 11), text: `Point`
```

Key details:
- Line/column are **0-indexed**
- `pattern: N` refers to the Nth pattern in the query file (0-indexed)
- Captures show the node range and optionally the text

## Decorator Handling

**Problem:** `class_definition` and `function_definition` nodes do NOT include decorators.

Example from `03_decorators/input.py`:
```python
# Line 21 (1-indexed)
@dataclass
@functools.total_ordering
class Priority:
    ...
```

tree-sitter reports: `start: (22, 0)` = line 23 (1-indexed) = `class Priority:`

**Solution:** Use `decorated_definition` to capture the full range including decorators.

```scheme
; Decorated class
(decorated_definition
  definition: (class_definition
    name: (identifier) @class.name)) @class.def

; Undecorated class
(class_definition
  name: (identifier) @class.name) @class.def
```

**Caveat:** This query produces DUPLICATES for decorated definitions:
- Pattern 0 matches `decorated_definition` (full range with decorators)
- Pattern 2 matches inner `class_definition` (without decorators)

**OCaml post-processing:** For each unique name, keep only the match with the
earliest `start_line`. This gives us decorator ranges without duplicates.

## Filtering Top-Level Definitions

tree-sitter captures ALL matching nodes, including nested ones (methods inside classes).
Filter by: `start_column == 0` for top-level definitions.
