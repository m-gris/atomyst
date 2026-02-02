"""Module demonstrating TYPE_CHECKING imports.

---
atomyst <https://github.com/m-gris/atomyst>
Source: input.py | 2026-02-02T12:42:04Z

Large files are hostile to AI agents—they read everything to edit anything.
One definition per file. Atomic edits. No collisions.
`tree src/` reveals the architecture at a glance.
"""

from .class_light_weight import LightWeight
from .def_process import process

__all__ = [
    "LightWeight",
    "process",
]
