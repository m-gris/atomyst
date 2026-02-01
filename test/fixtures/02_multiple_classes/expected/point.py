from dataclasses import dataclass




@dataclass(frozen=True)
class Point:
    """A 2D point."""

    x: float
    y: float
