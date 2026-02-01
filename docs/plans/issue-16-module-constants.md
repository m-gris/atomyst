# GitHub Issue #16: Module-level Constants Not Extracted

## Problem Statement

Atomyst extracts class and function definitions to separate files, but **module-level constants, variables, and assignments** that those definitions depend on are NOT extracted. This causes runtime `NameError` when the extracted code references them.

## Example

```python
# Original file
SQL_TYPE_MAPPING: Dict[str, str] = {"str": "text", "int": "integer"}

class FieldTypeInfo(StrictBaseModel):
    @field_validator("field_type")
    def validate_type(cls, v):
        if v not in SQL_TYPE_MAPPING:  # ← references module constant
            raise ValueError(...)
```

After atomization:
- `field_type_info.py` contains `FieldTypeInfo` class
- `SQL_TYPE_MAPPING` is **nowhere** — causes `NameError` at runtime

---

## Phase 1: Problem Decomposition

### 1.1 Reframed Problem Statement

**Goal**: Ensure that when a definition (class/function) is extracted to its own file, all module-level names it references are available in that file.

**Constraints**:
- Minimal changes to existing architecture
- No false positives (don't duplicate things unnecessarily)
- Must work with existing import handling
- Should not break incremental extraction workflow

**Success criteria**:
- Extracted code runs without `NameError` for module-level references
- Module-level constants appear in exactly the files that need them
- No silent breakage — warn if something can't be handled

### 1.2 Subproblem Decomposition

| Subproblem | Question to Answer | Dependencies |
|------------|-------------------|--------------|
| **S1: Detection** | What module-level items exist in the source file? | None |
| **S2: Classification** | Which items are constants vs variables vs type aliases? | S1 |
| **S3: Reference Analysis** | Which definitions reference which module-level items? | S1 |
| **S4: Placement Strategy** | Where should each module-level item go? | S2, S3 |
| **S5: Code Generation** | How to emit the items in extracted files? | S4 |
| **S6: Conflict Resolution** | What if multiple definitions need the same constant? | S3, S4 |

### 1.3 Key Unknowns

1. **Detection precision**: Should we parse module-level items with pyre-ast or tree-sitter?
2. **Reference detection**: Regex word-match (current) vs AST-based name extraction?
3. **Placement policy**: Copy to each file that needs it? Or shared `_constants.py`?
4. **Scope**: Handle all assignments, or only "obvious" constants?

---

## Phase 2: Solution Enumeration

### Path A: Copy Constants to Each File That Needs Them

**Summary**: Inline the constant definition into each extracted file that references it.

**Key insight**: Simple, local, no new files needed.

**Steps**:
1. Parse module-level assignments with pyre-ast
2. Build map: `constant_name → source_text`
3. For each extracted definition, find referenced constants (AST-based)
4. Prepend constant definitions to the extracted file

**Tradeoffs**:
| Dimension | Rating | Notes |
|-----------|--------|-------|
| Complexity | Low | Minimal new code |
| Duplication | High | Same constant in multiple files |
| Correctness | High | Each file is self-contained |
| Maintainability | Low | Editing constant requires editing all copies |

### Path B: Shared `_constants.py` Module

**Summary**: Extract all module-level constants to a shared file, import from there.

**Key insight**: Single source of truth, follows DRY principle.

**Steps**:
1. Parse module-level assignments with pyre-ast
2. Generate `_constants.py` with all constants
3. For each extracted definition, add `from ._constants import X, Y`
4. Update `__init__.py` to expose constants if needed

**Tradeoffs**:
| Dimension | Rating | Notes |
|-----------|--------|-------|
| Complexity | Medium | New file generation logic |
| Duplication | None | Single source of truth |
| Correctness | High | Consistent values |
| Maintainability | High | Edit in one place |
| Import overhead | Medium | Extra import per file |

### Path C: Smart Inlining with Deduplication

**Summary**: Copy to each file, but detect identical constants and warn/share.

**Key insight**: Balance between A and B — local when possible, shared when necessary.

**Steps**:
1. Parse module-level items, classify as "simple" (literals) vs "complex" (expressions)
2. Simple constants: inline into each file
3. Complex constants (or those used by 3+ definitions): extract to `_shared.py`
4. Generate appropriate imports

**Tradeoffs**:
| Dimension | Rating | Notes |
|-----------|--------|-------|
| Complexity | High | Classification logic, threshold decisions |
| Duplication | Low | Controlled duplication |
| Correctness | High | With care |
| Maintainability | Medium | Hybrid approach |

### Path D: Warn-Only Mode (MVP)

**Summary**: Detect and warn about missing constants, don't auto-fix.

**Key insight**: Fail loudly, let user decide.

**Steps**:
1. Parse module-level assignments
2. For each extracted definition, detect referenced constants
3. Emit warning: "FieldTypeInfo references SQL_TYPE_MAPPING which is not extracted"
4. User manually fixes

**Tradeoffs**:
| Dimension | Rating | Notes |
|-----------|--------|-------|
| Complexity | Very Low | Detection only |
| Duplication | N/A | No extraction |
| Correctness | High | No silent breakage |
| User experience | Poor | Manual work required |

---

## Phase 3: Recommendation

### Selected Path: B (Shared `_constants.py`) with Phased Rollout

**Rationale**:

| Criterion | Path B Score | Why |
|-----------|--------------|-----|
| Correctness | ✓✓✓ | Single source of truth, mutable objects work correctly |
| Simplicity | ✓✓ | Medium complexity, well-bounded scope |
| FP/Unix | ✓✓✓ | Single responsibility, clear separation |
| User Experience | ✓✓✓ | Predictable, familiar pattern |
| Edge Cases | ✓✓✓ | Handles all cases uniformly |

**Why NOT the others**:
- **Path A (inline)**: Violates DRY, breaks mutable objects, confusing output
- **Path C (hybrid)**: Added complexity without clear benefit, unpredictable behavior
- **Path D (warn-only)**: Good for MVP but incomplete long-term solution

### Phased Approach

**Phase 1 (MVP)**: Detection + Warning
- Surface the problem without changing output behavior
- Low risk, immediate feedback

**Phase 2**: Generate `_constants.py` + Imports
- Full solution
- Builds on Phase 1 detection

---

## Phase 4: Implementation Plan

### Phase 1: Detection and Warning (MVP)

#### Step 1.1: Extend `Python_parser` to Extract Constants

**File**: `lib/python_parser.mli`

Add new types and function:
```ocaml
type module_constant = {
  name : string;
  loc : location;
}

val extract_constants : string -> module_constant list
(** Extract module-level Assign, AnnAssign, TypeAlias statements *)
```

**File**: `lib/python_parser.ml`

Implement by parsing with pyre-ast and filtering for:
- `Statement.Assign` with simple `Name` target
- `Statement.AnnAssign` with `Name` target
- Skip `__all__`, `__name__`, etc. (dunder names)
- Skip augmented assignments (`+=`)

#### Step 1.2: Add Constant Reference Detection

**File**: `lib/extract.ml`

Add function similar to `find_sibling_references`:
```ocaml
val find_constant_references :
  constant_names:string list ->
  defn_content:string ->
  string list
(** Find which constants are referenced in a definition's content *)
```

Use existing regex word-boundary approach (`\bNAME\b`).

#### Step 1.3: Emit Warning

**File**: `bin/main.ml`

After extracting definitions:
1. Call `Python_parser.extract_constants source`
2. For each definition, call `find_constant_references`
3. If any references found, emit warning:
   ```
   ⚠ FieldTypeInfo references module-level constant(s): SQL_TYPE_MAPPING
     These are NOT extracted and may cause NameError at runtime.
   ```

---

### Phase 2: Generate `_constants.py`

#### Step 2.1: Extract Constant Source Text

**File**: `lib/python_parser.ml`

Extend `module_constant` to include source text:
```ocaml
type module_constant = {
  name : string;
  loc : location;
  (* New: raw source lines for this constant *)
}
```

#### Step 2.2: Build Constants File

**File**: `bin/main.ml`

Add `build_constants_file`:
```ocaml
let build_constants_file constants source_lines =
  (* Get import block for the original file *)
  (* Extract source lines for each constant *)
  (* Combine: imports + blank line + constants *)
  { Types.relative_path = "_constants.py"; content = ... }
```

#### Step 2.3: Generate Imports in Definition Files

**File**: `lib/extract.ml` or `bin/main.ml`

Modify `build_definition_file` to:
1. Call `find_constant_references` for the definition
2. If any constants referenced, prepend:
   ```python
   from ._constants import SQL_TYPE_MAPPING, ANOTHER_CONSTANT
   ```

#### Step 2.4: Include `_constants.py` in Output

**File**: `bin/main.ml`

Modify `plan_atomization` to:
1. Extract constants
2. Determine which constants are referenced by ANY definition
3. If any, generate `_constants.py`
4. Add to `output_files` list

---

## Files to Modify

| File | Phase | Changes |
|------|-------|---------|
| `lib/python_parser.mli` | 1 | Add `module_constant` type, `extract_constants` |
| `lib/python_parser.ml` | 1 | Implement `extract_constants` using pyre-ast |
| `lib/extract.ml` | 1 | Add `find_constant_references` |
| `bin/main.ml` | 1 | Add warning for unreferenced constants |
| `bin/main.ml` | 2 | Add `build_constants_file`, modify `plan_atomization` |
| `lib/extract.ml` | 2 | Add constant imports to definition files |

---

## Edge Cases

| Case | Handling |
|------|----------|
| No constants in file | Skip `_constants.py` generation |
| Constants used by no definitions | Still include in `_constants.py` (user may want them) |
| Mutable (`logger = getLogger(...)`) | Works correctly - single instance in `_constants.py` |
| Constants depending on constants | All in same file, order preserved from source |
| `__all__`, `__name__` | Skip (dunder names are metadata, not constants) |
| `x += 1` augmented assignment | Skip (implies mutation, not declaration) |
| Forward references in type hints | Works - imports resolve at runtime |

---

## Testing Strategy

### Unit Tests
- `test_python_parser.ml`: Test `extract_constants` for Assign, AnnAssign, TypeAlias
- `test_extract.ml`: Test `find_constant_references` detection

### Integration Tests
- New fixture: `test/fixtures/XX_constants/`
  - `input.py` with `SQL_TYPE_MAPPING` and class that uses it
  - `expected/_constants.py` with the constant
  - `expected/field_type_info.py` with `from ._constants import` line

### Manual Verification
```bash
# Create test file
echo 'SQL_TYPE = {"int": "INTEGER"}
class FieldInfo:
    def sql(self): return SQL_TYPE["int"]
' > /tmp/test.py

# Run atomyst
atomyst /tmp/test.py -o /tmp/out

# Verify
cat /tmp/out/_constants.py  # Should have SQL_TYPE
cat /tmp/out/field_info.py  # Should import from ._constants
python -c "from /tmp/out import FieldInfo; print(FieldInfo().sql())"  # Should work
```

---

## Open Questions (For Implementation Phase)

1. **Phasing**: Phase 1 (warning-only) first, or jump to Phase 2 (full solution)?

2. **Imports for `_constants.py`**: Copy ALL imports, or analyze which are needed?

3. **TypeVar handling**: Include `T = TypeVar("T")` in constants, or handle separately?

4. **Order preservation**: Maintain source order in `_constants.py`?

5. **Naming**: `_constants.py` vs `_shared.py` vs `_module_level.py`?

---

## Summary

This document presents:
- **Problem decomposition** into 6 subproblems (detection, classification, reference analysis, placement, generation, conflict resolution)
- **4 solution paths** with tradeoff analysis
- **Recommendation**: Path B (shared `_constants.py`) for its correctness, simplicity, and alignment with FP/Unix principles
- **Sketch** of implementation phases (details TBD based on user decisions)

The core insight: **single source of truth** is essential for mutable objects and maintainability. Inlining (Path A) violates this principle and creates subtle bugs.

---

*Status: Analysis complete. Awaiting user review before implementation planning.*
