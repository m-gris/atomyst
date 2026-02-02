from dataclasses import dataclass
from typing import Optional


from .class_point import Point


@dataclass
class Circle:
    """A circle with center and radius."""

    center: Point
    radius: float
    label: Optional[str] = None
