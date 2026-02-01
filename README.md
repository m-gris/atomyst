# atomyst

Atomize Python source files into one-definition-per-file structure.

**The Problem:** Large source files with multiple definitions are hostile to LLM coding agents. Agents must read entire files to edit one definition, context windows fill with irrelevant code, and parallel agents conflict on the same file.

**The Solution:** One definition per file. Directories are concepts. `__init__.py` is the public interface.

## Installation

```bash
# Clone and build
git clone https://github.com/yourorg/atomyst
cd atomyst
opam install . --deps-only
dune build

# Run
dune exec atomyst -- --help
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

## Features

- **Automatic import cleanup** - Unused imports are removed via `ruff` (silent if not installed)
- **Module docstring handling** - Skipped by default (with warning), since it describes the original file
- **Pragma handling** - File-level pragmas (`# mypy:`, `# type:`, etc.) skipped by default; use `--keep-pragmas` to include
- **Shebang preservation** - `#!/usr/bin/env python3` lines are kept
- **`__init__.py` generation** - Auto-generated with re-exports and `__all__`
- **TYPE_CHECKING blocks** - Preserved in import section

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
├── __init__.py     # from .user import User; from .order import Order
├── user.py         # User class with its imports
└── order.py        # Order class with its imports
```

With warnings:
```
⚠ Module docstring was NOT copied to extracted files.
  Review the original and distribute manually if needed.
⚠ Pragma comments (# mypy:, # type:, etc.) were skipped.
  Use --keep-pragmas to include them.
```

## Philosophy

> **Files are definitions. Directories are concepts. Index files are interfaces.**

| Element | Granularity |
|---------|-------------|
| Function | One file |
| Class | One file |
| Type/Struct | One file |
| Constants | Grouped by affinity |

### Why This Works

1. **Context efficiency** — Read 20 lines, not 300
2. **Atomic edits** — One concept, one file, one diff
3. **Structure as documentation** — `tree src/` reveals the architecture
4. **Parallel safety** — Multiple agents on different files cannot conflict

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
