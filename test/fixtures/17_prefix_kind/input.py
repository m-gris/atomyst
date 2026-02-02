"""Test prefix_kind flag with multiple definition types."""

from dataclasses import dataclass
from typing import Any


@dataclass
class UserProfile:
    """A user profile."""
    name: str
    email: str


def calculate_total(items: list[float]) -> float:
    """Calculate total from items."""
    return sum(items)
