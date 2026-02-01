from __future__ import annotations

from dataclasses import dataclass




@dataclass
class Child:
    """Child references Parent."""

    name: str
    parent: Parent | None = None
