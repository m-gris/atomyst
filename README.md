# atomyst

Atomize Python source files into one-definition-per-file structure.

## Install

```bash
uvx atomyst --help
```

Or install globally:

```bash
uv tool install atomyst
```

## Usage

### Batch mode (atomize entire file)

```bash
# Preview what would be created
atomyst mymodule.py --dry-run

# Atomize to output directory
atomyst mymodule.py -o output/
```

### Incremental mode (extract one definition)

```bash
# Preview extraction
atomyst mymodule.py --extract MyClass --dry-run

# Extract to current directory
atomyst mymodule.py --extract MyClass

# JSON output
atomyst mymodule.py --extract MyClass --format json
```

## Philosophy

One definition per file. Directories as concepts. `__init__.py` as the public interface.

See [ATOMIC_FILE_SYSTEM.md](./ATOMIC_FILE_SYSTEM.md) for the full philosophy.
