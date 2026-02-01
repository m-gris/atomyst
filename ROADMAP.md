# Atomyst

**Atomyst** — Atomize source files for the LLM era.

## The Problem

Large source files with multiple definitions are hostile to LLM coding agents:
- Agents must read entire files to edit one definition
- Context windows fill with irrelevant code
- Parallel agents conflict on the same file
- Git history mixes unrelated changes

## The Manifesto

> **Files are definitions. Directories are concepts. Index files are interfaces.**

### The Structure

```
concept/
  __init__.py          # exports: Foo, Bar, Baz (the interface)
  foo.py               # one definition
  bar.py               # one definition
  baz.py               # one definition
```

### The Rules

| Element | Granularity |
|---------|-------------|
| Function | One file |
| Class | One file |
| Type/Struct | One file |
| Constants | Grouped by affinity |

### Why This Works

1. **Context efficiency** — Read 20 lines, not 300. The entire file *is* the relevant part.
2. **Atomic edits** — One concept, one file, one diff. Minimal blast radius.
3. **Structure as documentation** — `tree src/` reveals the architecture.
4. **Parallel safety** — Multiple agents on different files cannot conflict.
5. **Session continuity** — New conversation reads one file to understand one thing.

### The Insight

The traditional question: *"Does this function belong in this file?"*

Becomes: *"Does this file belong in this directory?"*

Directories are concepts. Files are atoms. The filesystem is the architecture.

## What Atomyst Does

Given a large source file, atomyst:
1. Parses to identify top-level definitions (classes, functions, types)
2. Extracts each definition to its own file (preserving comments, formatting)
3. Generates an index file with re-exports
4. Leaves you with atomic, LLM-friendly structure

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        ATOMYST                              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │   PARSER     │    │  EXTRACTOR   │    │  GENERATOR   │  │
│  │ (tree-sitter)│───▶│    (pure)    │───▶│    (pure)    │  │
│  └──────────────┘    └──────────────┘    └──────────────┘  │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                  LANGUAGE CONFIG                      │  │
│  │  Extensible: add new languages via configuration      │  │
│  │  - definition node types                              │  │
│  │  - file naming convention                             │  │
│  │  - index file name & syntax                           │  │
│  │  - export/import syntax                               │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
                       Effect Boundary
                       (file I/O only)
```

**Key design goal:** Adding a new language should require only configuration, not code changes. The core algorithm is language-agnostic.

## Implementation Strategy

### Phase 0: Prototype (Python) ✓ COMPLETE
Quick validation using Python's stdlib `ast` + line slicing.
*Completed: successfully atomized real 3000-line files.*

### Phase 1: Production Tool (OCaml) ✓ COMPLETE
Rewritten in OCaml with tree-sitter for parsing.
Proper CLI, error handling, fixture-based tests.
*Completed: full feature parity, Python prototype retired.*

### Phase 2: Extensibility (Future)
Language configs as data (TOML/YAML).
Community can add languages without touching core.

## Design Decisions

### Why Tree-sitter?
- One parser infrastructure for many languages
- Concrete syntax tree with line/column info
- Battle-tested (GitHub, Neovim, Helix, Zed)

### Why Line Slicing (not AST unparsing)?
- Preserves comments and formatting exactly
- Simpler, no round-trip fidelity issues
- Tree-sitter gives line numbers; we slice text

### Import Handling
- Copy all imports to each extracted file
- Let language formatters (ruff, rustfmt) remove unused
- Smart import analysis is a future enhancement

## Success Criteria

1. `atomyst <file>` splits a 3000-line file into ~50 files in <1 second
2. Resulting code compiles/type-checks (imports may need formatter cleanup)
3. Git diff shows pure moves, no semantic changes
4. An LLM agent can read one file and understand one concept completely

## Non-Goals (For Now)

- Refactoring beyond splitting (renaming, reorganizing)
- Merging files (reverse atomization)
- IDE/LSP integration
