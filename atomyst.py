#!/usr/bin/env python3
"""
Atomyst - Atomize source files for the LLM era.

Prototype implementation using Python's ast + line slicing.

Architecture: Functional Core, Imperative Shell
- Data: immutable dataclasses
- Computations: pure functions (no I/O, no printing)
- Renderers: pure functions (data → str)
- Actions: read/write/print at edges only
"""

from __future__ import annotations

import ast
import json
import re
import sys
from dataclasses import dataclass
from enum import Enum, auto
from pathlib import Path
from typing import Literal, Sequence


# =============================================================================
# DOMAIN TYPES (Data)
# =============================================================================


class DefinitionKind(Enum):
    """Kind of top-level definition."""

    CLASS = auto()
    FUNCTION = auto()
    ASYNC_FUNCTION = auto()


@dataclass(frozen=True)
class Definition:
    """A top-level definition extracted from source."""

    name: str
    kind: DefinitionKind
    start_line: int  # 1-indexed, includes decorators
    end_line: int  # 1-indexed, inclusive


@dataclass(frozen=True)
class OutputFile:
    """A file to be written (pure data, no I/O)."""

    relative_path: str  # e.g., "foo.py" or "__init__.py"
    content: str

    @property
    def line_count(self) -> int:
        return self.content.count("\n")


@dataclass(frozen=True)
class AtomizePlan:
    """The complete plan for atomizing a source file (pure data)."""

    source_name: str
    definitions: tuple[Definition, ...]
    output_files: tuple[OutputFile, ...]
    import_block: str


@dataclass(frozen=True)
class AtomizeOutcome:
    """The outcome of an atomization operation (pure data)."""

    plan: AtomizePlan
    written_paths: tuple[Path, ...] | None  # None if dry-run
    output_dir: Path


@dataclass(frozen=True)
class ExtractionResult:
    """Result of extracting a single definition (pure data)."""

    extracted: OutputFile  # The extracted definition
    remainder: str  # The source with definition removed


# =============================================================================
# PURE FUNCTIONS (Computations) - No I/O, no side effects, no printing
# =============================================================================


def to_snake_case(name: str) -> str:
    """Convert PascalCase/camelCase to snake_case."""
    s1 = re.sub(r"(.)([A-Z][a-z]+)", r"\1_\2", name)
    return re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", s1).lower()


def extract_definitions(source: str) -> tuple[Definition, ...]:
    """
    Extract all top-level class and function definitions with their line ranges.

    Pure: str -> tuple[Definition, ...]
    """
    tree = ast.parse(source)

    def node_to_definition(node: ast.AST) -> Definition | None:
        match node:
            case ast.ClassDef(name=name, decorator_list=decorators, end_lineno=end):
                if end is None:
                    return None
                start = min((d.lineno for d in decorators), default=node.lineno)
                return Definition(name, DefinitionKind.CLASS, start, end)

            case ast.FunctionDef(name=name, decorator_list=decorators, end_lineno=end):
                if end is None:
                    return None
                start = min((d.lineno for d in decorators), default=node.lineno)
                return Definition(name, DefinitionKind.FUNCTION, start, end)

            case ast.AsyncFunctionDef(name=name, decorator_list=decorators, end_lineno=end):
                if end is None:
                    return None
                start = min((d.lineno for d in decorators), default=node.lineno)
                return Definition(name, DefinitionKind.ASYNC_FUNCTION, start, end)

            case _:
                return None

    definitions = [
        defn
        for node in ast.iter_child_nodes(tree)
        if (defn := node_to_definition(node)) is not None
    ]
    return tuple(definitions)


def extract_imports(lines: Sequence[str]) -> tuple[str, ...]:
    """
    Extract all import lines from the beginning of the file.

    Includes:
    - Module docstrings and shebangs
    - import and from statements
    - Multi-line imports (parenthesized)
    - TYPE_CHECKING blocks (if TYPE_CHECKING: ...)

    Pure: Sequence[str] -> tuple[str, ...]
    """
    result: list[str] = []
    in_imports = False
    paren_depth = 0
    in_type_checking = False
    type_checking_indent = 0

    for line in lines:
        stripped = line.strip()

        # Handle TYPE_CHECKING block
        if in_type_checking:
            # Calculate indentation of current line
            if stripped:
                current_indent = len(line) - len(line.lstrip())
                if current_indent > type_checking_indent:
                    result.append(line)
                    continue
                else:
                    # Block ended
                    in_type_checking = False
            else:
                # Empty line inside block
                result.append(line)
                continue

        # Detect start of TYPE_CHECKING block
        if stripped.startswith("if TYPE_CHECKING") or stripped == "if TYPE_CHECKING:":
            in_type_checking = True
            type_checking_indent = len(line) - len(line.lstrip())
            result.append(line)
            in_imports = True
            continue

        # Module docstring or shebang at start
        if not in_imports and (
            stripped.startswith("#")
            or stripped.startswith('"""')
            or stripped.startswith("'''")
        ):
            result.append(line)
            continue

        # Import statement
        if stripped.startswith(("import ", "from ")):
            in_imports = True
            result.append(line)
            paren_depth += line.count("(") - line.count(")")
            continue

        # Continuation of multi-line import
        if paren_depth > 0:
            result.append(line)
            paren_depth += line.count("(") - line.count(")")
            continue

        # Blank line in import section
        if in_imports and stripped == "":
            result.append(line)
            continue

        # Non-import, non-comment line ends the import section
        if stripped and not stripped.startswith(("import ", "from ", "#")):
            break

    return tuple(result)


def find_comment_start(lines: Sequence[str], start_line: int) -> int:
    """
    Look backwards to find where comments immediately preceding a definition begin.

    Pure: (lines, start_line) -> adjusted_start_line
    """
    idx = start_line - 2

    while idx >= 0:
        stripped = lines[idx].strip()
        if stripped.startswith("#"):
            idx -= 1
        elif stripped == "":
            break
        else:
            break

    return idx + 2


def build_definition_file(
    defn: Definition,
    lines: Sequence[str],
    import_block: str,
) -> OutputFile:
    """
    Build an output file for a single definition.

    Pure: (Definition, lines, imports) -> OutputFile
    """
    actual_start = find_comment_start(lines, defn.start_line)
    defn_lines = lines[actual_start - 1 : defn.end_line]
    defn_content = "".join(defn_lines)
    file_content = import_block + "\n\n" + defn_content.lstrip("\n")
    filename = to_snake_case(defn.name) + ".py"

    return OutputFile(relative_path=filename, content=file_content)


def build_init_file(definitions: Sequence[Definition]) -> OutputFile:
    """
    Build the __init__.py re-export file.

    Pure: Sequence[Definition] -> OutputFile
    """
    lines: list[str] = ['"""Auto-generated by atomyst."""\n\n']

    for defn in definitions:
        stem = to_snake_case(defn.name)
        lines.append(f"from .{stem} import {defn.name}\n")

    lines.append("\n__all__ = [\n")
    for defn in definitions:
        lines.append(f'    "{defn.name}",\n')
    lines.append("]\n")

    return OutputFile(relative_path="__init__.py", content="".join(lines))


def extract_one(source: str, name: str) -> ExtractionResult | None:
    """
    Extract a single definition by name from source.

    Returns the extracted definition as an OutputFile and the remaining source.
    Returns None if the definition is not found.

    Pure: (str, str) -> ExtractionResult | None
    """
    lines = source.splitlines(keepends=True)
    definitions = extract_definitions(source)
    import_lines = extract_imports(lines)
    import_block = "".join(import_lines)

    # Find the definition by name
    target = None
    for defn in definitions:
        if defn.name == name:
            target = defn
            break

    if target is None:
        return None

    # Build the extracted file
    extracted = build_definition_file(target, lines, import_block)

    # Build the remainder (source with definition removed)
    actual_start = find_comment_start(lines, target.start_line)
    before = lines[: actual_start - 1]
    after = lines[target.end_line :]

    # Clean up extra blank lines at the junction
    remainder_lines = before + after
    remainder = "".join(remainder_lines)

    return ExtractionResult(extracted=extracted, remainder=remainder)


def plan_atomization(source: str, source_name: str) -> AtomizePlan:
    """
    Create a complete atomization plan from source code.

    Pure: (str, str) -> AtomizePlan
    """
    lines = source.splitlines(keepends=True)
    definitions = extract_definitions(source)
    import_lines = extract_imports(lines)
    import_block = "".join(import_lines)

    definition_files = tuple(
        build_definition_file(defn, lines, import_block) for defn in definitions
    )
    init_file = build_init_file(definitions)
    output_files = definition_files + (init_file,)

    return AtomizePlan(
        source_name=source_name,
        definitions=definitions,
        output_files=output_files,
        import_block=import_block,
    )


# =============================================================================
# RENDERERS (Pure: Data -> str)
# =============================================================================


def render_plan_text(plan: AtomizePlan) -> str:
    """Render plan as human-readable text. Pure: AtomizePlan -> str."""
    lines: list[str] = []
    lines.append(f"Found {len(plan.definitions)} definitions in {plan.source_name}:")

    for defn in plan.definitions:
        kind_str = defn.kind.name.lower().replace("_", " ")
        lines.append(f"  {kind_str:15} {defn.name:40} lines {defn.start_line}-{defn.end_line}")

    lines.append(f"\nWill create {len(plan.output_files)} files:")
    for f in plan.output_files:
        lines.append(f"  {f.relative_path} ({f.line_count} lines)")

    return "\n".join(lines)


def render_plan_json(plan: AtomizePlan) -> str:
    """Render plan as JSON. Pure: AtomizePlan -> str."""
    data = {
        "source": plan.source_name,
        "definitions": [
            {
                "name": d.name,
                "kind": d.kind.name.lower(),
                "start_line": d.start_line,
                "end_line": d.end_line,
            }
            for d in plan.definitions
        ],
        "output_files": [
            {"path": f.relative_path, "lines": f.line_count}
            for f in plan.output_files
        ],
    }
    return json.dumps(data, indent=2)


def render_outcome_text(outcome: AtomizeOutcome) -> str:
    """Render outcome as human-readable text. Pure: AtomizeOutcome -> str."""
    lines: list[str] = [render_plan_text(outcome.plan), ""]

    if outcome.written_paths is None:
        lines.append("[DRY RUN] No files written.")
    else:
        lines.append(f"Created {len(outcome.written_paths)} files in {outcome.output_dir}/")

    return "\n".join(lines)


def render_error(message: str) -> str:
    """Render an error message. Pure: str -> str."""
    return f"Error: {message}"


# =============================================================================
# ACTIONS (Effects) - I/O happens here only
# =============================================================================


def read_source(path: Path) -> str:
    """Read source file. Action."""
    return path.read_text()


def write_files(files: Sequence[OutputFile], output_dir: Path) -> tuple[Path, ...]:
    """Write output files to disk. Action."""
    output_dir.mkdir(parents=True, exist_ok=True)
    created: list[Path] = []

    for f in files:
        path = output_dir / f.relative_path
        path.write_text(f.content)
        created.append(path)

    return tuple(created)


# =============================================================================
# MAIN (Orchestration) - Wiring only, single print at the end
# =============================================================================


def run(
    source_path: Path,
    output_dir: Path | None,
    dry_run: bool,
    output_format: Literal["text", "json"],
) -> tuple[int, str]:
    """
    Run atomization. Returns (exit_code, output_to_display).

    This is almost pure — takes explicit inputs, returns data.
    Only actual I/O is file read/write.
    """
    if not source_path.exists():
        return (1, render_error(f"{source_path} does not exist"))

    resolved_output_dir = output_dir or source_path.parent / source_path.stem

    # ACTION: Read
    source = read_source(source_path)

    # COMPUTATION: Plan (pure)
    plan = plan_atomization(source, source_path.name)

    if not plan.definitions:
        return (0, f"No definitions found in {source_path}")

    # ACTION: Write (or skip if dry-run)
    if dry_run:
        written_paths = None
    else:
        written_paths = write_files(plan.output_files, resolved_output_dir)

    # COMPUTATION: Build outcome (pure)
    outcome = AtomizeOutcome(
        plan=plan,
        written_paths=written_paths,
        output_dir=resolved_output_dir,
    )

    # RENDER: Data -> str (pure)
    if output_format == "json":
        output = render_plan_json(outcome.plan)
    else:
        output = render_outcome_text(outcome)

    return (0, output)


def main() -> int:
    """Entry point. Parses args, calls run(), prints once, exits."""
    import argparse

    parser = argparse.ArgumentParser(
        description="Atomize Python source files into one-definition-per-file structure."
    )
    parser.add_argument("source", type=Path, help="Source file to atomize")
    parser.add_argument(
        "-o", "--output",
        type=Path,
        help="Output directory (default: <source_stem>/)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be created without writing files",
    )
    parser.add_argument(
        "--format",
        choices=["text", "json"],
        default="text",
        help="Output format (default: text)",
    )

    args = parser.parse_args()

    # Run (returns data)
    exit_code, output = run(
        source_path=args.source,
        output_dir=args.output,
        dry_run=args.dry_run,
        output_format=args.format,
    )

    # Single print at the edge
    print(output)

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
