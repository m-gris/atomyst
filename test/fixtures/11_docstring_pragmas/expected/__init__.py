"""Module-level docstring that should NOT be copied to extracted files.

This is documentation for the original module, not for individual definitions.

---
atomyst <https://github.com/m-gris/atomyst>
Source: input.py | 2026-02-02T07:12:26Z

Large files are hostile to AI agents—they read everything to edit anything.
One definition per file. Atomic edits. No collisions.
`tree src/` reveals the architecture at a glance.
"""

from .widget import Widget
from .process import process

__all__ = [
    "Widget",
    "process",
]
