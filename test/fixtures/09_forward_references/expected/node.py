"""Module with circular/forward references between classes."""
from __future__ import annotations

from dataclasses import dataclass




@dataclass
class Node:
    """A node in a linked list."""

    value: int
    next: Node | None = None
