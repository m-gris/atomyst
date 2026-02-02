> **ATOMIZED** → Epic: atomyst-7en | 2026-02-02

# Plan: Binding Classification Architecture for Multi-Language Atomization

> **Link**: GitHub issue #23 (edge cases), #22 (logger fix - the trigger)

## Problem Statement

Module-level bindings have varying semantics that determine how they should be handled during atomization:
- Some are safe to centralize (`_constants.py`)
- Some must be replicated per-file (`__name__`, `__file__` dependent)
- Some must stay grouped (registries + their users)
- Some require user decision (mutable state)

Currently, logger bindings are special-cased in `main.ml` with Python-specific logic embedded in orchestration. This doesn't scale to:
1. Other Python edge cases (`__file__`, mutable state, registries)
2. Future language support (JS, TS, Rust)

---

## Solution: Binding Classification System

### Core Abstraction

```ocaml
(* lib/types.ml *)
type binding_strategy =
  | Centralize           (* Safe for _constants.py *)
  | ReplicatePerFile     (* __name__, __file__ dependent *)
  | KeepGrouped          (* Registry + decoratees - future *)
  | Warn of string       (* Mutable state - needs user attention *)

type classified_binding = {
  name : string;
  source_text : string;
  loc : Python_parser.location;
  strategy : binding_strategy;
  reason : string;        (* "depends on __name__", "mutable dict", etc. *)
}
```

### Architecture After Refactor

```
┌─────────────────────────────────────────────────────────────┐
│ main.ml (orchestration)                                     │
│   - Calls language-specific classifier                      │
│   - Handles classified_binding list generically             │
│   - No knowledge of __name__, __file__, logging patterns    │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ lib/binding_classifier.ml (NEW)                             │
│   - classify_bindings : source -> classified_binding list   │
│   - Pure computation: AST → classification                  │
│   - Contains ALL Python-specific pattern knowledge          │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ lib/python_parser.ml (extraction only)                      │
│   - extract_assignments : source -> raw_assignment list     │
│   - No classification logic, just AST extraction            │
└─────────────────────────────────────────────────────────────┘
```

---

## /rigor: Audit Current Behavior FIRST (Light)

**STOP. Before any code changes, document what exists via code comments and tests.**

### Audit Checklist (Phase 0)

- [ ] **A1**: Add docstring to `python_parser.ml` listing patterns currently detected
- [ ] **A2**: Add test cases that capture current behavior (snapshot tests)
- [ ] **A3**: Note known bugs in test file comments (e.g., mutable collections extracted)

### Audit Deliverables

```ocaml
(* test/ocaml/test_binding_classifier.ml - document current behavior *)

(** AUDIT: Current binding handling as of 2026-02-02

    Detected patterns:
    - [x] Simple constants (FOO = 42) → _constants.py
    - [x] Logger bindings (logging.getLogger(__name__)) → replicate per-file
    - [ ] __file__ dependent → NOT DETECTED (extracted to _constants.py - BUG)
    - [ ] Mutable collections → NOT DETECTED (extracted to _constants.py - BUG)
*)
```

**Gate**: Audit documented in test file. Proceed when baseline captured.

---

## /dual-tdd: Types First, Tests Second, Implementation Third

### Phase 1: Types (Compile-Time Specification)

**Goal**: Define the type system that constrains valid implementations.

#### 1.1 Define `binding_strategy` type

```ocaml
(* lib/types.ml - add to existing *)

type binding_strategy =
  | Centralize
  | ReplicatePerFile
  | Warn of string

type classified_binding = {
  name : string;
  source_text : string;
  strategy : binding_strategy;
  reason : string;
}
```

#### 1.2 Define classifier interface

```ocaml
(* lib/binding_classifier.mli - NEW *)

(** Classify module-level bindings by their atomization strategy.

    This is the ONLY place that knows about Python-specific patterns
    like logging.getLogger(__name__) or Path(__file__).

    The orchestration layer (main.ml) treats all bindings uniformly
    based on their strategy, with no language-specific knowledge.
*)

val classify_bindings : string -> Types.classified_binding list
(** [classify_bindings source] extracts and classifies all module-level
    bindings from Python source code.

    Returns bindings tagged with their strategy:
    - [Centralize]: Safe to extract to _constants.py
    - [ReplicatePerFile]: Must be copied to each file that uses it
    - [Warn reason]: Requires user attention (e.g., mutable state)
*)

val partition_by_strategy :
  Types.classified_binding list ->
  (Types.classified_binding list  (* centralize *)
   * Types.classified_binding list (* replicate *)
   * Types.classified_binding list (* warn *))
(** Partition bindings by strategy for processing *)
```

**Verification**: `just build` compiles with new types. Types ARE the spec.

---

### Phase 2: Tests (Behavioral Specification)

**Goal**: Write failing tests that define expected behavior BEFORE implementation.

#### 2.1 Test file structure

```ocaml
(* test/ocaml/test_binding_classifier.ml - NEW *)

open Atomyst

(* === CENTRALIZE strategy tests === *)

let test_simple_constant_centralizes () =
  let source = "FOO = 42" in
  let bindings = Binding_classifier.classify_bindings source in
  Alcotest.(check int) "one binding" 1 (List.length bindings);
  let b = List.hd bindings in
  Alcotest.(check string) "name" "FOO" b.name;
  match b.strategy with
  | Types.Centralize -> ()
  | _ -> Alcotest.fail "expected Centralize"

let test_annotated_constant_centralizes () =
  let source = "MAX_SIZE: int = 100" in
  let bindings = Binding_classifier.classify_bindings source in
  match (List.hd bindings).strategy with
  | Types.Centralize -> ()
  | _ -> Alcotest.fail "expected Centralize"

(* === REPLICATE_PER_FILE strategy tests === *)

let test_logger_getlogger_replicates () =
  let source = {|import logging
logger = logging.getLogger(__name__)|} in
  let bindings = Binding_classifier.classify_bindings source in
  let logger_binding = List.find (fun b -> b.name = "logger") bindings in
  match logger_binding.strategy with
  | Types.ReplicatePerFile -> ()
  | _ -> Alcotest.fail "expected ReplicatePerFile"

let test_file_path_replicates () =
  let source = {|from pathlib import Path
BASE_DIR = Path(__file__).parent|} in
  let bindings = Binding_classifier.classify_bindings source in
  let base_dir = List.find (fun b -> b.name = "BASE_DIR") bindings in
  match base_dir.strategy with
  | Types.ReplicatePerFile -> ()
  | _ -> Alcotest.fail "expected ReplicatePerFile for __file__ dependent"

(* === WARN strategy tests === *)

let test_mutable_dict_warns () =
  let source = "_cache = {}" in
  let bindings = Binding_classifier.classify_bindings source in
  match (List.hd bindings).strategy with
  | Types.Warn reason ->
    Alcotest.(check bool) "mentions mutable" true
      (String.contains reason "mutable" || String.contains reason "dict")
  | _ -> Alcotest.fail "expected Warn for mutable dict"

let test_mutable_list_warns () =
  let source = "_items = []" in
  let bindings = Binding_classifier.classify_bindings source in
  match (List.hd bindings).strategy with
  | Types.Warn _ -> ()
  | _ -> Alcotest.fail "expected Warn for mutable list"
```

#### 2.2 Run tests - they MUST fail

```bash
just test-ocaml
# Expected: Compilation error (Binding_classifier module doesn't exist)
# This is correct! Tests define the spec before implementation.
```

**Gate**: Tests written and reviewed. They define the contract.

---

### Phase 3: Implementation (Make Tests Pass)

**Goal**: Minimal implementation that satisfies the type system and passes tests.

#### 3.1 Implement detection predicates

```ocaml
(* lib/binding_classifier.ml *)

(** Check if expression depends on __name__ *)
let rec contains_dunder_name (expr : PyreAst.Concrete.Expression.t) : bool =
  match expr with
  | Expression.Name { id; _ } -> Identifier.to_string id = "__name__"
  | Expression.Call { args; _ } -> List.exists contains_dunder_name args
  | Expression.Attribute { value; _ } -> contains_dunder_name value
  | Expression.BinOp { left; right; _ } ->
    contains_dunder_name left || contains_dunder_name right
  | _ -> false

(** Check if expression depends on __file__ *)
let rec contains_dunder_file (expr : PyreAst.Concrete.Expression.t) : bool =
  (* Similar pattern to above *)
  ...

(** Check if expression is a mutable collection literal *)
let is_mutable_literal (expr : PyreAst.Concrete.Expression.t) : bool =
  match expr with
  | Expression.Dict _ -> true
  | Expression.List _ -> true
  | Expression.Set _ -> true
  | _ -> false
```

#### 3.2 Implement classifier

```ocaml
let classify_assignment (name : string) (value : PyreAst.Concrete.Expression.t option)
    (source_text : string) : classified_binding =
  let strategy, reason = match value with
    | Some v when contains_dunder_name v ->
      (ReplicatePerFile, "depends on __name__")
    | Some v when contains_dunder_file v ->
      (ReplicatePerFile, "depends on __file__")
    | Some v when is_mutable_literal v ->
      (Warn "mutable collection - shared state semantics unclear",
       "mutable collection")
    | _ ->
      (Centralize, "simple constant")
  in
  { name; source_text; strategy; reason }
```

#### 3.3 Run tests - they MUST pass

```bash
just test-ocaml
# All binding_classifier tests should pass
```

**Gate**: All tests green. Implementation matches spec.

---

### Phase 4: Integration (Wire Into Orchestration)

**Goal**: Replace ad-hoc logger handling in main.ml with generic strategy handling.

#### 4.1 Refactor `plan_atomization`

**Before** (current - lines 248-294 in main.ml):
```ocaml
(* Python-specific logger handling embedded in orchestration *)
let logger_bindings = Python_parser.extract_logger_bindings source in
let logger_var_names = List.map ... in
(* ... 40+ lines of logger-specific logic ... *)
```

**After**:
```ocaml
(* Generic binding handling - no Python knowledge *)
let classified = Binding_classifier.classify_bindings source in
let (centralize, replicate, warn) =
  Binding_classifier.partition_by_strategy classified in

(* Warn about ambiguous bindings *)
List.iter (fun b ->
  Printf.eprintf "⚠ %s: %s\n" b.name b.reason
) warn;

(* Handle replicate-per-file bindings generically *)
let replicate_for_defn defn_content =
  List.filter_map (fun b ->
    if Extract.references_name b.name defn_content
    then Some b.source_text
    else None
  ) replicate
  |> String.concat "\n"
in
```

#### 4.2 Regression test

```bash
# Run ALL existing tests
just test-ocaml
just test-fixtures

# Verify logger behavior unchanged
diff <(git show HEAD:test/fixtures/18_logger_binding/expected/) \
     test/fixtures/18_logger_binding/expected/
```

**Gate**: All existing tests pass. No regressions.

---

### Phase 5: Extend (New Edge Cases)

**Goal**: Add detection for remaining gh-23 edge cases.

Each edge case follows the same TDD cycle:
1. Write failing test
2. Add detection predicate
3. Make test pass
4. Add fixture

#### 5.1 `__file__` dependent bindings

```ocaml
(* Test first *)
let test_pathlib_file_replicates () =
  let source = {|BASE = Path(__file__).parent / "data"|} in
  ...
```

#### 5.2 Mutable collections

```ocaml
(* Test first *)
let test_empty_dict_warns () =
  let source = "_registry = {}" in
  ...
```

---

## Files to Modify

| File | Change | Phase |
|------|--------|-------|
| `lib/types.ml` | Add `binding_strategy`, `classified_binding` | 1 |
| `lib/binding_classifier.mli` | NEW: Interface | 1 |
| `lib/binding_classifier.ml` | NEW: Implementation | 3 |
| `lib/dune` | Add binding_classifier to library | 1 |
| `test/ocaml/test_binding_classifier.ml` | NEW: Tests | 2 |
| `test/ocaml/dune` | Add test_binding_classifier | 2 |
| `bin/main.ml` | Replace logger logic with generic handling | 4 |
| `lib/python_parser.ml` | Remove logger_binding type (moved) | 4 |
| `test/fixtures/19_mutable_state/` | NEW: Fixture | 5 |
| `test/fixtures/20_file_dependent/` | NEW: Fixture | 5 |

---

## Verification Checklist

### After Phase 1 (Types)
- [ ] `just build` compiles
- [ ] Types documented with purpose

### After Phase 2 (Tests)
- [ ] Tests compile but fail (or don't compile due to missing module)
- [ ] Test cases cover: Centralize, ReplicatePerFile, Warn
- [ ] Edge cases from gh-23 have test stubs

### After Phase 3 (Implementation)
- [ ] All new tests pass
- [ ] `just test-ocaml` green

### After Phase 4 (Integration)
- [ ] `just test-fixtures` green (no regressions)
- [ ] Logger fixture (18) still works
- [ ] No Python-specific code in main.ml orchestration

### After Phase 5 (Extend)
- [ ] New fixtures for mutable state, __file__ patterns
- [ ] Warnings emitted for ambiguous patterns
- [ ] gh-23 edge cases addressed

---

## Out of Scope

- `KeepGrouped` strategy (registries) - requires cross-definition analysis, future work
- Multi-language support - architecture enables it, but no JS/TS impl yet
- Interactive prompts for `Warn` strategy - just emit warnings for now

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Regression in existing atomization | Run full test suite after Phase 4 |
| Breaking logger behavior | Logger fixture (18) is the regression test |
| Over-engineering | Start with 3 strategies only, add more when needed |
| AST pattern matching complexity | Follow existing `is_logger_getname_call` pattern |
