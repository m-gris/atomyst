from __future__ import annotations

from dataclasses import dataclass


from .child import Child


@dataclass
class Parent:
    """Parent references Child."""

    name: str
    children: list[Child] | None = None
