"""Module with async functions.

---
atomyst <https://github.com/m-gris/atomyst>
Source: input.py | 2026-02-02T10:15:46Z

Large files are hostile to AI agents—they read everything to edit anything.
One definition per file. Atomic edits. No collisions.
`tree src/` reveals the architecture at a glance.
"""

from .fetch_data import fetch_data
from .process_items import process_items
from .async_client import AsyncClient

__all__ = [
    "fetch_data",
    "process_items",
    "AsyncClient",
]
