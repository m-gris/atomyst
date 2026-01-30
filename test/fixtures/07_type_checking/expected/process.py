"""Module demonstrating TYPE_CHECKING imports."""
from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from heavy_module import HeavyType
    from another_module import AnotherType




def process(item: AnotherType) -> str:
    """Function using TYPE_CHECKING import."""
    return str(item)
