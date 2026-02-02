# atomyst

Atomize Python source files into one-definition-per-file structure.

## The Problem

Traditional Python idioms favor rich modules with multiple related definitions per file. This made sense when humans read code top-to-bottom and navigation meant `grep` and `less`.

The LLM era introduces new constraints:

- **Context windows are finite** — every irrelevant line degrades attention
- **Agents must read before editing** — large files mean slow iteration
- **Parallel agents need isolation** — file-level conflicts require coordination

Large files are hostile to AI agents. They read everything to edit anything.

## The Solution

> **Files are definitions. Directories are concepts. `__init__.py` is the interface.**

One definition per file. The tree *is* the architecture:

```bash
$ tree models/
models/
├── __init__.py     # Public API: from models import User, Order
├── user.py         # 25 lines — one class
└── order.py        # 30 lines — one class
```

The pre-LLM idiom of "rich modules" optimized for human sequential reading. This structure optimizes for **random access by context-limited agents**.

## Installation

```bash
# Clone and build
git clone https://github.com/m-gris/atomyst
cd atomyst
opam install . --deps-only
dune build

# Install (optional)
dune install

# Run
atomyst --help
# or: dune exec atomyst -- --help
```

## Usage

### List definitions (no changes)

```bash
# Show all definitions in file order
atomyst mymodule.py --list

# Group by kind (classes, functions, etc.)
atomyst mymodule.py --list --organized

# JSON output
atomyst mymodule.py --list --format json
```

### Atomize entire file (batch mode)

```bash
# Preview what would be created
atomyst mymodule.py --dry-run

# Atomize to output directory (default: mymodule/)
atomyst mymodule.py

# Specify output directory
atomyst mymodule.py -o output/
```

### Extract single definition (incremental mode)

```bash
# Preview extraction
atomyst mymodule.py --extract MyClass --dry-run

# Extract to current directory
atomyst mymodule.py --extract MyClass

# Extract to specific directory
atomyst mymodule.py --extract MyClass -o output/
```

### Generate manifest (preserve original structure)

```bash
# Generate MANIFEST.yaml alongside extracted files
atomyst mymodule.py --manifest yaml

# JSON or Markdown format
atomyst mymodule.py --manifest json
atomyst mymodule.py --manifest md
```

## Features

- **Automatic import cleanup** - Unused imports are removed via `ruff` (silent if not installed)
- **Relative import adjustment** - `from .foo import X` becomes `from ..foo import X` when extracting to subdirectory
- **Sibling import generation** - Cross-references between definitions get automatic `from .sibling import Name` imports
- **Module docstring preservation** - Original module docstring is embedded in `__init__.py` with atomization metadata
- **Pragma handling** - File-level pragmas (`# mypy:`, `# type:`, etc.) skipped by default; use `--keep-pragmas` to include
- **Shebang preservation** - `#!/usr/bin/env python3` lines are kept
- **`__init__.py` generation** - Auto-generated with re-exports, `__all__`, and provenance metadata
- **Safe original file removal** - Original is removed if git-tracked and clean; use `--keep-original` to preserve
- **TYPE_CHECKING blocks** - Preserved in import section
- **Manifest generation** - `--manifest yaml|json|md` creates a MANIFEST file preserving original definition order

## Example

Given `models.py`:

```python
"""Domain models for the application."""
# mypy: disable-error-code=assignment

from dataclasses import dataclass
from typing import Optional

@dataclass
class User:
    name: str
    email: Optional[str] = None

@dataclass
class Order:
    user: User
    total: float
```

Running `atomyst models.py` creates:

```
models/
├── __init__.py     # Docstring + metadata + re-exports
├── user.py         # User class with its imports
└── order.py        # Order class with its imports
```

The generated `__init__.py`:

```python
"""Domain models for the application.

---
atomyst <https://github.com/m-gris/atomyst>
Source: models.py | 2026-02-02T12:34:56Z

Large files are hostile to AI agents—they read everything to edit anything.
One definition per file. Atomic edits. No collisions.
`tree src/` reveals the architecture at a glance.
"""

from .user import User
from .order import Order

__all__ = [
    "User",
    "Order",
]
```

The original `models.py` is removed (if git-tracked and clean). Use `--keep-original` to preserve it.

## Philosophy

> **Files are definitions. Directories are concepts. `__init__.py` is the interface.**

| Element | Granularity | Rationale |
|---------|-------------|-----------|
| Function | One file | Atomic edit unit |
| Class | One file | Atomic edit unit |
| Dataclass/Type | One file | Atomic edit unit |
| Constants/Enums | Grouped per concept | Inert data, no behavior to isolate |

### Why This Works

1. **Context efficiency** — An agent editing `normalize.py` reads 20 lines, not 300. The entire file *is* the relevant part.
2. **Atomic edits** — One concept, one file, one diff. Git history per file traces one thing's evolution.
3. **Structure as documentation** — `tree src/` reveals the architecture. Every `mkdir` is an architectural decision.
4. **Parallel safety** — Multiple agents on different files cannot conflict. File-level isolation provides natural coordination.
5. **Session continuity** — New conversation reads one file to catch up, not an entire module.

### Comparison with Traditional Approach

| Aspect | Rich modules (traditional) | Atomic (one definition per file) |
|--------|---------------------------|----------------------------------|
| File size | 100-500 lines | 20-80 lines |
| Concept boundary | Within file | Within directory |
| Navigation | Scroll/search within file | Tree navigation |
| LLM context cost | High (read whole file) | Low (read one definition) |
| Parallel edits | Conflict-prone | Conflict-free |
| Git archaeology | Mixed history per file | Clean history per definition |

See [ROADMAP.md](./ROADMAP.md) for implementation details.

## Development

```bash
# Build
just build

# Run tests
just test

# Run fixture tests
just test-fixtures

# Run on a file
just run path/to/file.py --dry-run
```
