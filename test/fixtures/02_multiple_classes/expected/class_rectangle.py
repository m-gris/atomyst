from dataclasses import dataclass
from typing import Optional


from .class_point import Point


@dataclass(frozen=True)
class Rectangle:
    """A rectangle defined by two points."""

    top_left: Point
    bottom_right: Point

    @property
    def width(self) -> float:
        return self.bottom_right.x - self.top_left.x

    @property
    def height(self) -> float:
        return self.bottom_right.y - self.top_left.y
