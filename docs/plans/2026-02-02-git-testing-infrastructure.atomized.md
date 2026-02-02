> **ATOMIZED** → Epic: atomyst-xlo | 2026-02-02

# Plan: Proper Git Testing Infrastructure + Fix #21

## Problem Decomposition

### Core Issue
`rewrite.ml`'s `fix_consumer_imports` depends on git (`git ls-files`) but has NO tests. This led to bug #21: crash when tracked files don't exist on disk.

### Sub-problems
1. **Test helpers are duplicated** - `test_git_utils.ml` has helpers that should be shared
2. **No tests for `fix_consumer_imports`** - git interaction is untested
3. **Bug #21** - `open_in` without `Sys.file_exists` check

### Scope
- `lib/git_utils.ml` - already tested (5 test cases)
- `lib/rewrite.ml` - `find_git_root`, `find_python_files`, `fix_consumer_imports` UNTESTED
- `test/ocaml/test_git_utils.ml` - has reusable helpers

---

## Solution: FP/Unix Approach

### Principle: Separate Concerns
1. **Data**: Git repo state (tracked files, existence)
2. **Computation**: Pure logic for import rewriting
3. **Action**: Shell commands to git

### Existing Pattern (Keep)
`test_git_utils.ml` already does it right:
- Isolated temp dirs
- Real git operations (not mocked)
- `Fun.protect ~finally` for cleanup

---

## Implementation Plan

### Phase 1: Extract Shared Test Helpers

**File**: `test/ocaml/test_helpers.ml` (new)

```ocaml
(** Shared test utilities for git-dependent tests *)

val make_temp_dir : string -> string
val rm_rf : string -> unit
val run_in_dir : string -> string -> unit
val write_file : string -> string -> unit
val with_temp_git_repo : (string -> 'a) -> 'a
```

The key helper:
```ocaml
let with_temp_git_repo f =
  let dir = make_temp_dir "test" in
  Fun.protect ~finally:(fun () -> rm_rf dir) (fun () ->
    run_in_dir dir "git init";
    run_in_dir dir "git config user.email 'test@test.com'";
    run_in_dir dir "git config user.name 'Test'";
    f dir
  )
```

### Phase 2: Update test_git_utils.ml

Replace inline helpers with:
```ocaml
open Test_helpers
```

Verify existing 5 tests still pass.

### Phase 3: Add Tests for rewrite.ml Git Functions

**File**: `test/ocaml/test_rewrite.ml` (extend existing)

Add new test group:

```ocaml
(* Git integration tests *)

let test_find_git_root () =
  with_temp_git_repo (fun dir ->
    let file = Filename.concat dir "test.py" in
    write_file file "x = 1";
    let result = Rewrite.find_git_root file in
    Alcotest.(check (option string)) "finds root" (Some dir) result
  )

let test_find_python_files () =
  with_temp_git_repo (fun dir ->
    write_file (Filename.concat dir "a.py") "x = 1";
    write_file (Filename.concat dir "b.py") "y = 2";
    run_in_dir dir "git add .";
    run_in_dir dir "git commit -m 'add'";
    let files = Rewrite.find_python_files dir in
    Alcotest.(check int) "finds 2 files" 2 (List.length files)
  )

let test_fix_consumer_imports_skips_deleted_files () =
  with_temp_git_repo (fun dir ->
    (* Setup: create and track files *)
    write_file (Filename.concat dir "source.py") "class Foo: pass";
    write_file (Filename.concat dir "consumer.py") "from source import Foo";
    run_in_dir dir "git add .";
    run_in_dir dir "git commit -m 'initial'";

    (* Delete source.py from disk (but still tracked in git) *)
    Sys.remove (Filename.concat dir "source.py");

    (* This should NOT crash *)
    let result = Rewrite.fix_consumer_imports
      ~atomized_file:(Filename.concat dir "source.py")
      ~defined_names:["Foo"]
      ~reexports:[]
    in
    (* Should succeed or return appropriate error, not crash *)
    match result with
    | Rewrite.Fixed _ -> ()  (* OK *)
    | Rewrite.Error _ -> ()  (* OK - graceful error *)
    | _ -> Alcotest.fail "unexpected result"
  )
```

### Phase 4: Fix Bug #21

**File**: `lib/rewrite.ml`

Already partially done. Verify the fix at line ~435:

```ocaml
else if not (Sys.file_exists file_path) then
  (* Skip files that are tracked but deleted from disk *)
  process_files rest
else begin
  let ic = open_in file_path in
  ...
```

### Phase 5: Expose Functions for Testing

**File**: `lib/rewrite.mli`

Add to interface (if not already exposed):
```ocaml
val find_git_root : string -> string option
val find_python_files : string -> string list
```

---

## Files to Modify

| File | Change |
|------|--------|
| `test/ocaml/test_helpers.ml` | NEW: shared test utilities |
| `test/ocaml/dune` | Add test_helpers to libraries |
| `test/ocaml/test_git_utils.ml` | Use shared helpers |
| `test/ocaml/test_rewrite.ml` | Add git integration tests |
| `lib/rewrite.ml` | Fix #21 (already done, verify) |
| `lib/rewrite.mli` | Expose `find_git_root`, `find_python_files` |

---

## Verification

1. `just build` - compiles
2. `just test-ocaml` - all tests pass including new ones
3. Manual test: delete a tracked file, run atomize → should not crash

---

## Dual-TDD Approach

1. **Types first**: `test_helpers.mli` defines interface
2. **Tests second**: Write failing tests for `fix_consumer_imports`
3. **Implementation**: Fix passes tests

---

## Out of Scope

- Replacing shell commands with ocaml-git/VCS library (future enhancement)
- Property-based testing with QCheck (nice-to-have)
- Mocking git (not recommended per research)
