from dataclasses import dataclass
from typing import Optional




@dataclass
class Circle:
    """A circle with center and radius."""

    center: Point
    radius: float
    label: Optional[str] = None
