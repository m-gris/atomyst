"""Module-level docstring that should NOT be copied to extracted files.

This is documentation for the original module, not for individual definitions.
"""
# mypy: disable-error-code=assignment
# type: ignore
# ruff: noqa: E501

from dataclasses import dataclass


@dataclass
class Widget:
    """A widget with a name."""

    name: str


def process(x: int) -> int:
    """Process a value."""
    return x * 2
