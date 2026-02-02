"""Test prefix_kind flag with multiple definition types.

---
atomyst <https://github.com/m-gris/atomyst>
Source: input.py | 2026-02-02T07:13:04Z

Large files are hostile to AI agents—they read everything to edit anything.
One definition per file. Atomic edits. No collisions.
`tree src/` reveals the architecture at a glance.
"""

from .class_user_profile import UserProfile
from .def_calculate_total import calculate_total

__all__ = [
    "UserProfile",
    "calculate_total",
]
