"""Module demonstrating comment handling.

---
atomyst <https://github.com/m-gris/atomyst>
Source: input.py | 2026-02-02T07:12:25Z

Large files are hostile to AI agents—they read everything to edit anything.
One definition per file. Atomic edits. No collisions.
`tree src/` reveals the architecture at a glance.
"""

from .with_comment import WithComment
from .with_blank_line import WithBlankLine
from .no_comment import NoComment

__all__ = [
    "WithComment",
    "WithBlankLine",
    "NoComment",
]
