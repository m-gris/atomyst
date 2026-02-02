"""Module demonstrating decorator handling.

---
atomyst <https://github.com/m-gris/atomyst>
Source: input.py | 2026-02-02T07:12:25Z

Large files are hostile to AI agents—they read everything to edit anything.
One definition per file. Atomic edits. No collisions.
`tree src/` reveals the architecture at a glance.
"""

from .log_calls import log_calls
from .priority import Priority
from .expensive_computation import expensive_computation

__all__ = [
    "log_calls",
    "Priority",
    "expensive_computation",
]
