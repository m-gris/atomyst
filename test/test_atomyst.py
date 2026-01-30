#!/usr/bin/env python3
"""
Tests for atomyst.

Architecture: Functional Core testing style
- Pure functions tested with assertions, no mocks
- Fixtures provide input/expected pairs
- Golden tests compare output against committed expectations
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

# Add parent to path so we can import atomyst
sys.path.insert(0, str(Path(__file__).parent.parent))

from atomyst import (
    Definition,
    DefinitionKind,
    OutputFile,
    build_init_file,
    extract_definitions,
    extract_imports,
    find_comment_start,
    plan_atomization,
    to_snake_case,
)


# =============================================================================
# UNIT TESTS: to_snake_case (Pure function)
# =============================================================================


class TestToSnakeCase:
    """Test name conversion from PascalCase/camelCase to snake_case."""

    @pytest.mark.parametrize(
        "input_name,expected",
        [
            ("SimpleClass", "simple_class"),
            ("HTTPServer", "http_server"),
            ("XMLParser", "xml_parser"),
            ("MyHTTPClient", "my_http_client"),
            ("AWSLambdaHandler", "aws_lambda_handler"),
            ("A", "a"),
            ("AB", "ab"),
            ("ABCDef", "abc_def"),
            ("getHTTPResponse", "get_http_response"),
            ("simple_function", "simple_function"),  # Already snake_case
            ("already_snake_case", "already_snake_case"),
            ("ABC", "abc"),
            ("IOError", "io_error"),
            ("getID", "get_id"),
            ("HTMLParser", "html_parser"),
        ],
    )
    def test_conversion(self, input_name: str, expected: str) -> None:
        assert to_snake_case(input_name) == expected


# =============================================================================
# UNIT TESTS: extract_definitions (Pure function)
# =============================================================================


class TestExtractDefinitions:
    """Test extraction of top-level definitions from source."""

    def test_single_class(self) -> None:
        source = '''
class Foo:
    pass
'''
        defs = extract_definitions(source)
        assert len(defs) == 1
        assert defs[0].name == "Foo"
        assert defs[0].kind == DefinitionKind.CLASS

    def test_single_function(self) -> None:
        source = '''
def bar():
    pass
'''
        defs = extract_definitions(source)
        assert len(defs) == 1
        assert defs[0].name == "bar"
        assert defs[0].kind == DefinitionKind.FUNCTION

    def test_async_function(self) -> None:
        source = '''
async def fetch():
    pass
'''
        defs = extract_definitions(source)
        assert len(defs) == 1
        assert defs[0].name == "fetch"
        assert defs[0].kind == DefinitionKind.ASYNC_FUNCTION

    def test_multiple_definitions(self) -> None:
        source = '''
class Foo:
    pass

def bar():
    pass

class Baz:
    pass
'''
        defs = extract_definitions(source)
        assert len(defs) == 3
        assert [d.name for d in defs] == ["Foo", "bar", "Baz"]

    def test_decorated_class(self) -> None:
        source = '''
@dataclass
class Foo:
    x: int
'''
        defs = extract_definitions(source)
        assert len(defs) == 1
        assert defs[0].name == "Foo"
        assert defs[0].start_line == 2  # Decorator line
        assert defs[0].end_line == 4

    def test_multiple_decorators(self) -> None:
        source = '''
@decorator1
@decorator2
@decorator3
def foo():
    pass
'''
        defs = extract_definitions(source)
        assert len(defs) == 1
        assert defs[0].start_line == 2  # First decorator

    def test_nested_class_not_extracted(self) -> None:
        source = '''
class Outer:
    class Inner:
        pass
'''
        defs = extract_definitions(source)
        assert len(defs) == 1
        assert defs[0].name == "Outer"  # Only top-level

    def test_method_not_extracted(self) -> None:
        source = '''
class Foo:
    def method(self):
        pass
'''
        defs = extract_definitions(source)
        assert len(defs) == 1  # Only the class, not the method

    def test_empty_file(self) -> None:
        source = ""
        defs = extract_definitions(source)
        assert len(defs) == 0

    def test_only_imports(self) -> None:
        source = '''
import os
from pathlib import Path
'''
        defs = extract_definitions(source)
        assert len(defs) == 0


# =============================================================================
# UNIT TESTS: extract_imports (Pure function)
# =============================================================================


class TestExtractImports:
    """Test extraction of import block from source lines."""

    def test_simple_imports(self) -> None:
        lines = [
            "import os\n",
            "from pathlib import Path\n",
            "\n",
            "class Foo:\n",
            "    pass\n",
        ]
        imports = extract_imports(lines)
        assert "import os\n" in imports
        assert "from pathlib import Path\n" in imports

    def test_multiline_import(self) -> None:
        lines = [
            "from typing import (\n",
            "    List,\n",
            "    Dict,\n",
            ")\n",
            "\n",
            "class Foo:\n",
        ]
        imports = extract_imports(lines)
        assert len(imports) == 5  # 4 import lines + blank

    def test_module_docstring_preserved(self) -> None:
        lines = [
            '"""Module docstring."""\n',
            "\n",
            "import os\n",
            "\n",
            "class Foo:\n",
        ]
        imports = extract_imports(lines)
        assert '"""Module docstring."""\n' in imports

    def test_shebang_and_docstring(self) -> None:
        lines = [
            "#!/usr/bin/env python3\n",
            '"""Docstring."""\n',
            "\n",
            "import os\n",
        ]
        imports = extract_imports(lines)
        assert "#!/usr/bin/env python3\n" in imports


# =============================================================================
# UNIT TESTS: find_comment_start (Pure function)
# =============================================================================


class TestFindCommentStart:
    """Test detection of comments preceding definitions."""

    def test_comment_directly_above(self) -> None:
        lines = [
            "import os\n",
            "\n",
            "# Comment line 1\n",
            "# Comment line 2\n",
            "class Foo:\n",
            "    pass\n",
        ]
        # Definition starts at line 5 (1-indexed)
        start = find_comment_start(lines, 5)
        assert start == 3  # Comments start at line 3

    def test_blank_line_breaks_comment(self) -> None:
        lines = [
            "# Orphan comment\n",
            "\n",
            "class Foo:\n",
            "    pass\n",
        ]
        # Definition starts at line 3 (1-indexed)
        start = find_comment_start(lines, 3)
        assert start == 3  # Blank line breaks, start at class

    def test_no_comment(self) -> None:
        lines = [
            "import os\n",
            "\n",
            "class Foo:\n",
            "    pass\n",
        ]
        start = find_comment_start(lines, 3)
        assert start == 3  # No comment, start at class


# =============================================================================
# UNIT TESTS: build_init_file (Pure function)
# =============================================================================


class TestBuildInitFile:
    """Test generation of __init__.py content."""

    def test_single_definition(self) -> None:
        defs = [Definition("Foo", DefinitionKind.CLASS, 1, 5)]
        init = build_init_file(defs)
        assert init.relative_path == "__init__.py"
        assert "from .foo import Foo" in init.content
        assert '"Foo"' in init.content

    def test_multiple_definitions(self) -> None:
        defs = [
            Definition("Foo", DefinitionKind.CLASS, 1, 5),
            Definition("bar", DefinitionKind.FUNCTION, 7, 10),
            Definition("BazQux", DefinitionKind.CLASS, 12, 20),
        ]
        init = build_init_file(defs)
        assert "from .foo import Foo" in init.content
        assert "from .bar import bar" in init.content
        assert "from .baz_qux import BazQux" in init.content


# =============================================================================
# INTEGRATION TESTS: Fixtures
# =============================================================================


FIXTURES_DIR = Path(__file__).parent / "fixtures"


def get_fixture_dirs() -> list[Path]:
    """Get all fixture directories."""
    if not FIXTURES_DIR.exists():
        return []
    return sorted(
        d for d in FIXTURES_DIR.iterdir() if d.is_dir() and (d / "input.py").exists()
    )


@pytest.mark.parametrize(
    "fixture_dir",
    get_fixture_dirs(),
    ids=lambda d: d.name,
)
class TestFixtures:
    """Golden tests using fixture directories."""

    def test_definition_count(self, fixture_dir: Path) -> None:
        """Verify we extract the expected number of definitions."""
        input_file = fixture_dir / "input.py"
        expected_dir = fixture_dir / "expected"

        source = input_file.read_text()
        plan = plan_atomization(source, input_file.name)

        # Count expected files (excluding __init__.py)
        expected_files = [
            f for f in expected_dir.iterdir() if f.name != "__init__.py" and f.suffix == ".py"
        ]
        assert len(plan.definitions) == len(expected_files)

    def test_output_file_names(self, fixture_dir: Path) -> None:
        """Verify output files have correct names."""
        input_file = fixture_dir / "input.py"
        expected_dir = fixture_dir / "expected"

        source = input_file.read_text()
        plan = plan_atomization(source, input_file.name)

        expected_names = {f.name for f in expected_dir.iterdir() if f.suffix == ".py"}
        actual_names = {f.relative_path for f in plan.output_files}

        assert actual_names == expected_names

    def test_init_file_content(self, fixture_dir: Path) -> None:
        """Verify __init__.py has all re-exports."""
        input_file = fixture_dir / "input.py"
        expected_dir = fixture_dir / "expected"

        source = input_file.read_text()
        plan = plan_atomization(source, input_file.name)

        init_file = next(f for f in plan.output_files if f.relative_path == "__init__.py")
        expected_init = (expected_dir / "__init__.py").read_text()

        # Compare normalized (ignoring whitespace differences)
        assert init_file.content.strip() == expected_init.strip()


# =============================================================================
# PROPERTY TESTS: Invariants
# =============================================================================


class TestInvariants:
    """Test invariants that should hold for any valid input."""

    def test_line_ranges_dont_overlap(self) -> None:
        """Definition line ranges should be disjoint."""
        source = '''
class Foo:
    pass

class Bar:
    pass

def baz():
    pass
'''
        defs = extract_definitions(source)
        for i, d1 in enumerate(defs):
            for d2 in defs[i + 1 :]:
                # Ranges should not overlap
                assert d1.end_line < d2.start_line or d2.end_line < d1.start_line

    def test_all_definitions_in_init(self) -> None:
        """Every extracted definition should appear in __init__.py."""
        source = '''
class Foo:
    pass

class Bar:
    pass

def baz():
    pass
'''
        plan = plan_atomization(source, "test.py")
        init = next(f for f in plan.output_files if f.relative_path == "__init__.py")

        for defn in plan.definitions:
            assert defn.name in init.content


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
