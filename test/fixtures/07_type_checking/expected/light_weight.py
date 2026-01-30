"""Module demonstrating TYPE_CHECKING imports."""
from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from heavy_module import HeavyType
    from another_module import AnotherType




@dataclass
class LightWeight:
    """A class that references heavy types only for type checking."""

    name: str
    heavy: HeavyType | None = None
