"""Test file with module-level constants.

---
atomyst <https://github.com/m-gris/atomyst>
Source: input.py | 2026-02-02T07:12:26Z

Large files are hostile to AI agents—they read everything to edit anything.
One definition per file. Atomic edits. No collisions.
`tree src/` reveals the architecture at a glance.
"""

from .query import Query
from .response import Response

__all__ = [
    "Query",
    "Response",
]
