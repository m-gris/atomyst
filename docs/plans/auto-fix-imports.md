# Auto-Fix Consumer Imports After Atomization

## Before Starting

1. **Initialize beads context:**
   ```bash
   cd /Users/marc/DATA_PROG/OCAML/atomyst
   bd prime
   ```

2. **Copy this plan to project:**
   ```bash
   cp /Users/marc/.claude/plans/staged-herding-allen.md docs/plans/auto-fix-imports.md
   ```

3. **Create beads epic and tasks** (see Beads Breakdown section below)

---

## Problem Statement

When atomyst atomizes a Python file, consumers that relied on "re-exports" break. Example:

```python
# domain_models.py (BEFORE)
from pydantic import Field
from .common import StrictBaseModel

class Query(StrictBaseModel): ...
```

```python
# consumer.py
from .domain_models import Field, StrictBaseModel, Query  # re-exports!
```

After atomization, `Field` and `StrictBaseModel` aren't in `domain_models/__init__.py`, breaking consumers.

**Goal:** Atomyst automatically rewrites consumer imports to use original sources:
```python
# consumer.py (AFTER)
from pydantic import Field
from .common import StrictBaseModel
from .domain_models import Query  # actual definition
```

---

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| When to fix | During atomize (automatic) | One command does everything |
| Codebase scope | Git root | Respects .gitignore, predictable boundary |
| Edge case handling | Fail fast | Better to stop than corrupt imports |
| Implementation | Tree-sitter | Already a dependency, proper parsing |

---

## Edge Cases (Fail Fast)

| Case | Example | Behavior |
|------|---------|----------|
| Star imports | `from .domain_models import *` | **FAIL** — Cannot determine what's imported |
| Aliased imports | `from .dm import X as Y` | **HANDLE** — Preserve alias |
| Multi-line parens | `from .dm import (\n X,\n Y\n)` | **HANDLE** — Parse correctly |
| TYPE_CHECKING | `if TYPE_CHECKING: from ...` | **HANDLE** — Still an import |
| Comments inline | `from .x import Y  # note` | **HANDLE** — Preserve comment |
| Mixed import | `from .dm import Reexport, Defn` | **HANDLE** — Split into two imports |

---

## Implementation Steps

### Step 1: Find Git Root
```ocaml
let git_root () =
  (* git rev-parse --show-toplevel *)
```
- Returns absolute path to repository root
- Fail if not in a git repo

### Step 2: Scan Python Files
```ocaml
let find_python_files root =
  (* git ls-files '*.py' *)
```
- Respects .gitignore
- Returns list of relative paths

### Step 3: Resolve Target Module Path
```ocaml
let module_path_of_file file =
  (* Convert "src/models/domain.py" to "src.models.domain" *)
```
- Handle `__init__.py` as package
- Handle relative import dots based on consumer location

### Step 4: Create Import Query
Extend `queries/imports.scm` to capture:
- Module name (with dots for relative)
- All imported names (with aliases)
- Line/column positions for replacement

### Step 5: Parse Consumer Imports
```ocaml
let find_imports_from consumer_file target_module =
  (* Run tree-sitter query, filter to matching module *)
```
- Returns list of `{name; alias; is_reexport; original_source; position}`

### Step 6: Classify Imports
```ocaml
let classify_import name ~definitions ~reexports =
  if List.mem name definitions then `Definition
  else if List.mem_assoc name reexports then `Reexport (assoc name reexports)
  else `Unknown (* fail fast *)
```

### Step 7: Generate Replacement Text
```ocaml
let rewrite_import import ~definitions ~reexports =
  (* Split into:
     - from <original_source> import <reexport_names>
     - from <target_module> import <definition_names>
  *)
```
- Preserve aliases
- Preserve inline comments
- Handle multi-line formatting

### Step 8: Apply Changes
```ocaml
let apply_rewrites file rewrites =
  (* Read file, apply rewrites in reverse position order, write *)
```
- Process bottom-to-top to preserve positions
- Atomic write (temp file + rename)

### Step 9: Report
```ocaml
let report_changes changes =
  (*
  Fixed imports in 3 files:
    consumer.py: Field → pydantic, StrictBaseModel → .common
    other.py: log_msg → ..utils.logging
  *)
```

---

## Files to Modify

| File | Change |
|------|--------|
| `lib/extract.ml` | Add `find_imports_from_module`, `classify_import` |
| `lib/extract.mli` | Export new functions |
| `lib/rewrite.ml` | **NEW** — Import rewriting logic |
| `lib/rewrite.mli` | **NEW** — Interface |
| `bin/main.ml` | Integrate into `run_atomize` |
| `queries/imports.scm` | Enhance to capture positions |

---

## Verification

```bash
# 1. Create test case
mkdir -p /tmp/test_fix/{pkg,consumer}
cat > /tmp/test_fix/pkg/models.py << 'EOF'
from typing import Optional
from .common import Base

class Query(Base):
    pass
EOF

cat > /tmp/test_fix/pkg/common.py << 'EOF'
class Base:
    pass
EOF

cat > /tmp/test_fix/consumer/use.py << 'EOF'
from ..pkg.models import Optional, Base, Query
EOF

# 2. Initialize git
cd /tmp/test_fix && git init && git add -A && git commit -m "init"

# 3. Run atomize
atomyst pkg/models.py

# 4. Verify consumer was fixed
cat consumer/use.py
# Expected:
# from typing import Optional
# from ..pkg.common import Base
# from ..pkg.models import Query
```

---

## Beads Breakdown

```bash
EPIC=$(bd create --title="Auto-fix consumer imports" --type=epic --priority=1 --description="Automatically rewrite consumer imports when atomizing to fix re-export breakage" | grep -oE 'atomyst-[a-z0-9]+')

bd create --title="Find git root and scan Python files" --type=task --priority=1 --parent=$EPIC
bd create --title="Create tree-sitter import query with positions" --type=task --priority=1 --parent=$EPIC
bd create --title="Resolve module paths from file paths" --type=task --priority=1 --parent=$EPIC
bd create --title="Classify imports as definition vs reexport" --type=task --priority=1 --parent=$EPIC
bd create --title="Generate replacement import text" --type=task --priority=1 --parent=$EPIC
bd create --title="Apply rewrites atomically to files" --type=task --priority=2 --parent=$EPIC
bd create --title="Integrate into run_atomize flow" --type=task --priority=2 --parent=$EPIC
bd create --title="Handle edge cases: aliases, multi-line, comments" --type=task --priority=1 --parent=$EPIC
bd create --title="Fail fast on star imports" --type=task --priority=1 --parent=$EPIC
bd create --title="Add verification tests" --type=task --priority=2 --parent=$EPIC
```

---

## Future Enhancements (Not This PR)

- `--dry-run` for import fixing (preview changes)
- `--no-fix-imports` flag to disable auto-fix
- Parallel processing for large codebases
- Interactive mode for ambiguous cases
