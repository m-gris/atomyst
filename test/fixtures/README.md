# Test Fixtures

Each fixture is a directory containing:

```
NN_descriptive_name/
├── input.py          # Source file to atomize
└── expected/         # Expected output directory
    ├── __init__.py   # Re-export file
    ├── foo.py        # Extracted definition
    └── bar.py        # Extracted definition
```

## Adding a New Fixture

1. Create directory: `mkdir test/fixtures/NN_name`
2. Write `input.py` with the scenario to test
3. Generate expected: `python atomyst.py test/fixtures/NN_name/input.py -o test/fixtures/NN_name/expected`
4. Review the output manually
5. Run tests: `pytest test/test_atomyst.py -k "NN_name"`
6. Commit both `input.py` and `expected/`

## Current Fixtures

| # | Name | What it Tests |
|---|------|---------------|
| 01 | simple_class | Basic single class extraction |
| 02 | multiple_classes | Multiple classes, inter-class references |
| 03 | decorators | Single and stacked decorators |
| 04 | comments | Comment attachment vs orphaning |
| 05 | name_conversion | PascalCase, acronyms, edge cases |
| 06 | async_functions | async def extraction |
| 07 | type_checking | TYPE_CHECKING imports |
| 08 | module_level_code | TypeVar, constants, __all__ (NOT extracted) |
| 09 | forward_references | Self-referential and circular types |

## Naming Convention

- Use sequential numbers: `01_`, `02_`, ...
- Use snake_case for names
- Be descriptive but concise
