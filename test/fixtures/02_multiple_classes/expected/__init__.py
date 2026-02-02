"""Module with multiple classes demonstrating extraction.

---
atomyst <https://github.com/m-gris/atomyst>
Source: input.py | 2026-02-02T14:33:46Z

Large files are hostile to AI agents—they read everything to edit anything.
One definition per file. Atomic edits. No collisions.
`tree src/` reveals the architecture at a glance.
"""

from .class_point import Point
from .class_rectangle import Rectangle
from .class_circle import Circle

__all__ = [
    "Point",
    "Rectangle",
    "Circle",
]
