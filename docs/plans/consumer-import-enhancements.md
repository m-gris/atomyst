# Next Steps: Consumer Import Enhancement

## Before Starting

1. **Initialize beads context:**
   ```bash
   cd /Users/marc/DATA_PROG/OCAML/atomyst
   bd prime
   ```

2. **Copy this plan to project:**
   ```bash
   cp /Users/marc/.claude/plans/staged-herding-allen.md docs/plans/consumer-import-enhancements.md
   ```

3. **Create beads epic and tasks** (see Beads Breakdown section below)

---

## Status: Auto-Fix Consumer Imports ✓ COMPLETE

The core feature is implemented and tested:
- Tree-sitter query parses Python imports with positions
- Consumer imports classified as Definition vs Reexport vs Unknown
- Rewrites generated preserving aliases
- Atomic file writes with reverse position ordering
- Integration tests in `test/ocaml/test_rewrite.ml`
- Fixture at `test/fixtures/13_consumer_rewrite/`

---

## Feature 1: `--preserve-reexports` Flag

### Problem

Library authors with external consumers may WANT re-exports preserved. The current behavior always rewrites consumers, which works for monorepos but breaks external packages.

### Solution

Add `--preserve-reexports` flag to skip consumer import rewriting.

### Implementation

**File: `bin/main.ml`**

1. Add flag definition (~line 370):
```ocaml
let preserve_reexports_arg =
  let doc = "Skip fixing consumer imports. Use when re-exports are intentional (library code with external consumers)." in
  Arg.(value & flag & info ["preserve-reexports"] ~doc)
```

2. Update `main` signature (~line 331):
```ocaml
let main source_path output_dir dry_run format_opt keep_pragmas manifest_opt preserve_reexports =
```

3. Pass to `run_atomize` (~line 165):
```ocaml
let run_atomize source_path output_dir dry_run format_opt keep_pragmas manifest_opt preserve_reexports =
```

4. Conditional skip (~line 202):
```ocaml
if potential_reexports <> [] && not preserve_reexports then begin
  (* existing fix logic *)
end
```

5. Adjust warning message (~line 149):
```ocaml
let warnings = if potential_reexports <> [] && not preserve_reexports then
  "Potential re-exports detected and consumers fixed." :: warnings
else if potential_reexports <> [] then
  "Potential re-exports detected (--preserve-reexports enabled, consumers NOT fixed)." :: warnings
else warnings in
```

### Verification

```bash
# Without flag: consumers get fixed
atomyst pkg/models.py
cat consumer/use.py  # Should show split imports

# With flag: consumers untouched
atomyst --preserve-reexports pkg/models.py
cat consumer/use.py  # Should be unchanged
```

---

## Feature 2: Detailed Import Fix Reporting

### Problem

Current output only shows count:
```
✓ Fixed imports in 3 consumer file(s)
```

Users need to see WHAT changed WHERE.

### Solution

Return detailed fix information and format it clearly.

### Implementation

**File: `lib/rewrite.mli`** (~line 44)

Extend the return type:
```ocaml
type import_fix_detail = {
  file_path : string;
  names_moved : (string * string * string) list;  (* name, from_module, to_module *)
}

type fix_result =
  | Fixed of {
      rewrites : rewrite list;
      files_changed : int;
      details : import_fix_detail list;
    }
  | StarImportError of { file : string; line : int }
  | Error of string
```

**File: `lib/rewrite.ml`**

1. Define the new type (~line 27):
```ocaml
type import_fix_detail = {
  file_path : string;
  names_moved : (string * string * string) list;
}
```

2. Track details during rewriting (~line 450 in `fix_consumer_imports`):
   - Collect `(name, original_target, new_module)` for each rewrite
   - Group by file path
   - Return in `Fixed` constructor

**File: `bin/main.ml`** (~line 238)

Extend reporting:
```ocaml
| Some (Rewrite.Fixed { rewrites = _; files_changed; details }) ->
  if files_changed > 0 then begin
    print_endline (Printf.sprintf "\n✓ Fixed imports in %d consumer file(s):" files_changed);
    List.iter (fun (detail : Rewrite.import_fix_detail) ->
      print_endline (Printf.sprintf "  %s:" detail.file_path);
      List.iter (fun (name, _from, to_mod) ->
        print_endline (Printf.sprintf "    %s → %s" name to_mod)
      ) detail.names_moved
    ) details
  end
```

### Expected Output

```
✓ Fixed imports in 2 consumer file(s):
  consumer/use_models.py:
    Field → pydantic
    StrictBaseModel → .common
  other/client.py:
    log_msg → ..utils.logging
```

### Verification

Run atomyst on test fixture and verify detailed output appears.

---

## Files to Modify

| File | Change |
|------|--------|
| `lib/rewrite.mli` | Add `import_fix_detail` type, extend `fix_result` |
| `lib/rewrite.ml` | Track and return details during rewrite |
| `bin/main.ml` | Add `--preserve-reexports` flag, detailed reporting |
| `test/ocaml/test_rewrite.ml` | Update tests for new return type |

---

## Beads Breakdown

```bash
# Epic 1: --preserve-reexports flag
EPIC1=$(bd create --title="Add --preserve-reexports flag" --type=epic --priority=2 --description="Escape hatch for library authors who want to keep re-exports in __init__.py without rewriting consumers" | grep -oE 'atomyst-[a-z0-9]+')

bd create --title="Add --preserve-reexports Cmdliner arg" --type=task --priority=2 --parent=$EPIC1
bd create --title="Thread flag through run_atomize" --type=task --priority=2 --parent=$EPIC1
bd create --title="Conditional skip of fix_consumer_imports" --type=task --priority=2 --parent=$EPIC1
bd create --title="Adjust warning messages for flag" --type=task --priority=2 --parent=$EPIC1
bd create --title="Test --preserve-reexports behavior" --type=task --priority=2 --parent=$EPIC1

# Epic 2: Detailed import reporting
EPIC2=$(bd create --title="Detailed import fix reporting" --type=epic --priority=2 --description="Show exactly which imports moved where, not just file count" | grep -oE 'atomyst-[a-z0-9]+')

bd create --title="Add import_fix_detail type to rewrite.mli" --type=task --priority=2 --parent=$EPIC2
bd create --title="Track details during fix_consumer_imports" --type=task --priority=2 --parent=$EPIC2
bd create --title="Format detailed output in main.ml" --type=task --priority=2 --parent=$EPIC2
bd create --title="Update tests for new fix_result shape" --type=task --priority=2 --parent=$EPIC2
```

---

## Testing Strategy

### Unit Tests (test_rewrite.ml)
- Verify `import_fix_detail` captures correct name movements
- Test that `--preserve-reexports` leaves consumers unchanged

### Integration Tests
- Run on `test/fixtures/13_consumer_rewrite/`
- Verify detailed output format matches expected
- Verify flag behavior with and without

---

## Priority

Both features are P2 (nice-to-have, not blocking):
- Core functionality works
- These are polish/UX improvements
- Can be done in any order

---

## Future Enhancements (Not This PR)

- `--dry-run` for import fixing (preview without writing)
- `--verbose` to toggle detail level
- JSON output format for programmatic consumption
- Parallel processing for large codebases
