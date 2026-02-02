"""Module with async functions.

---
atomyst <https://github.com/m-gris/atomyst>
Source: input.py | 2026-02-02T12:42:04Z

Large files are hostile to AI agents—they read everything to edit anything.
One definition per file. Atomic edits. No collisions.
`tree src/` reveals the architecture at a glance.
"""

from .async_def_fetch_data import fetch_data
from .async_def_process_items import process_items
from .class_async_client import AsyncClient

__all__ = [
    "fetch_data",
    "process_items",
    "AsyncClient",
]
