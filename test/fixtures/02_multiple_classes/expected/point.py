from dataclasses import dataclass
from typing import Optional




@dataclass(frozen=True)
class Point:
    """A 2D point."""

    x: float
    y: float
