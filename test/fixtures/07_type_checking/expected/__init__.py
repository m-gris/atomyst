"""Module demonstrating TYPE_CHECKING imports.

---
atomyst <https://github.com/m-gris/atomyst>
Source: input.py | 2026-02-02T07:12:25Z

Large files are hostile to AI agents—they read everything to edit anything.
One definition per file. Atomic edits. No collisions.
`tree src/` reveals the architecture at a glance.
"""

from .light_weight import LightWeight
from .process import process

__all__ = [
    "LightWeight",
    "process",
]
