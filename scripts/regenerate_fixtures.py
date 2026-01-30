#!/usr/bin/env python3
"""
Regenerate test fixtures from current atomyst implementation.

Usage:
    python scripts/regenerate_fixtures.py [fixture_name]

If fixture_name is provided, only that fixture is regenerated.
Otherwise, all fixtures are regenerated.
"""

from __future__ import annotations

import sys
from pathlib import Path

# Add parent to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from atomyst import extract_one, plan_atomization


FIXTURES_DIR = Path(__file__).parent.parent / "test" / "fixtures"


def regenerate_batch_fixture(fixture_dir: Path) -> None:
    """Regenerate a batch fixture (input.py -> expected/)."""
    input_file = fixture_dir / "input.py"
    expected_dir = fixture_dir / "expected"

    if not input_file.exists():
        print(f"  Skipping {fixture_dir.name}: no input.py")
        return

    source = input_file.read_text()
    plan = plan_atomization(source, input_file.name)

    if not plan.definitions:
        print(f"  Skipping {fixture_dir.name}: no definitions found")
        return

    expected_dir.mkdir(exist_ok=True)

    for output_file in plan.output_files:
        path = expected_dir / output_file.relative_path
        path.write_text(output_file.content)

    print(f"  {fixture_dir.name}: {len(plan.output_files)} files")


def regenerate_incremental_fixture(fixture_dir: Path) -> None:
    """Regenerate an incremental fixture (input.py -> extract_*/expected_*)."""
    input_file = fixture_dir / "input.py"

    if not input_file.exists():
        print(f"  Skipping {fixture_dir.name}: no input.py")
        return

    source = input_file.read_text()

    # Find all extract_* subdirectories
    for subdir in fixture_dir.iterdir():
        if not subdir.is_dir() or not subdir.name.startswith("extract_"):
            continue

        name = subdir.name.replace("extract_", "")
        # Convert snake_case to PascalCase for class names
        class_name = "".join(word.capitalize() for word in name.split("_"))

        result = extract_one(source, class_name)
        if result is None:
            print(f"  {fixture_dir.name}/{subdir.name}: definition '{class_name}' not found")
            continue

        (subdir / f"expected_{name}.py").write_text(result.extracted.content)
        (subdir / "expected_remainder.py").write_text(result.remainder)

        print(f"  {fixture_dir.name}/{subdir.name}: regenerated")


def main() -> int:
    """Main entry point."""
    target = sys.argv[1] if len(sys.argv) > 1 else None

    print("Regenerating fixtures...")

    for fixture_dir in sorted(FIXTURES_DIR.iterdir()):
        if not fixture_dir.is_dir():
            continue

        if target and fixture_dir.name != target:
            continue

        # Determine fixture type by structure
        if (fixture_dir / "expected").exists() or not any(
            d.name.startswith("extract_") for d in fixture_dir.iterdir() if d.is_dir()
        ):
            regenerate_batch_fixture(fixture_dir)
        else:
            regenerate_incremental_fixture(fixture_dir)

    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
