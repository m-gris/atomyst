"""Module with circular/forward references between classes.

---
atomyst <https://github.com/m-gris/atomyst>
Source: input.py | 2026-02-02T14:33:46Z

Large files are hostile to AI agents—they read everything to edit anything.
One definition per file. Atomic edits. No collisions.
`tree src/` reveals the architecture at a glance.
"""

from .class_node import Node
from .class_tree import Tree
from .class_parent import Parent
from .class_child import Child

__all__ = [
    "Node",
    "Tree",
    "Parent",
    "Child",
]
