"""Module with various module-level code that should NOT be extracted.

---
atomyst <https://github.com/m-gris/atomyst>
Source: input.py | 2026-02-02T12:42:05Z

Large files are hostile to AI agents—they read everything to edit anything.
One definition per file. Atomic edits. No collisions.
`tree src/` reveals the architecture at a glance.
"""

from .class_container import Container
from .def_process_value import process_value

__all__ = [
    "Container",
    "process_value",
]
