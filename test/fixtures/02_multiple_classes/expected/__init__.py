"""Module with multiple classes demonstrating extraction.

---
atomyst <https://github.com/m-gris/atomyst>
Source: input.py | 2026-02-02T07:12:25Z

Large files are hostile to AI agents—they read everything to edit anything.
One definition per file. Atomic edits. No collisions.
`tree src/` reveals the architecture at a glance.
"""

from .point import Point
from .rectangle import Rectangle
from .circle import Circle

__all__ = [
    "Point",
    "Rectangle",
    "Circle",
]
