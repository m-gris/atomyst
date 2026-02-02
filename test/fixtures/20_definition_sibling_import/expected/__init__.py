"""Test: definitions that reference sibling definitions need prefixed imports."""
    """A data class referenced by a function."""
    """Function that returns a sibling class - needs import with prefix.

---
atomyst <https://github.com/m-gris/atomyst>
Source: input.py | 2026-02-02T14:25:51Z

Large files are hostile to AI agents—they read everything to edit anything.
One definition per file. Atomic edits. No collisions.
`tree src/` reveals the architecture at a glance.
"""

from .class_slot_match_result import SlotMatchResult
from .def_process_slot import process_slot

__all__ = [
    "SlotMatchResult",
    "process_slot",
]
