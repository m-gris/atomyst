"""Test: constants that reference sibling definitions need prefixed imports."""
    """A handler function referenced by a constant.

---
atomyst <https://github.com/m-gris/atomyst>
Source: input.py | 2026-02-02T14:00:30Z

Large files are hostile to AI agents—they read everything to edit anything.
One definition per file. Atomic edits. No collisions.
`tree src/` reveals the architecture at a glance.
"""

from .def__hacky_features_handler import _hacky_features_handler

__all__ = [
    "_hacky_features_handler",
]
