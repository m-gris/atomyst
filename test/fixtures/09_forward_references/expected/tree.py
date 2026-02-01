from __future__ import annotations

from dataclasses import dataclass




@dataclass
class Tree:
    """A binary tree node."""

    value: int
    left: Tree | None = None
    right: Tree | None = None
