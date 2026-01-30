"""Module with multiple classes demonstrating extraction."""

from dataclasses import dataclass
from typing import Optional


@dataclass(frozen=True)
class Point:
    """A 2D point."""

    x: float
    y: float


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


@dataclass
class Circle:
    """A circle with center and radius."""

    center: Point
    radius: float
    label: Optional[str] = None
