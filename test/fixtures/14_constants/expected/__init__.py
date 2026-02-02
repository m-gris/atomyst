"""Test file with module-level constants.

---
atomyst <https://github.com/m-gris/atomyst>
Source: input.py | 2026-02-02T12:42:05Z

Large files are hostile to AI agents—they read everything to edit anything.
One definition per file. Atomic edits. No collisions.
`tree src/` reveals the architecture at a glance.
"""

from .class_query import Query
from .class_response import Response

__all__ = [
    "Query",
    "Response",
]
