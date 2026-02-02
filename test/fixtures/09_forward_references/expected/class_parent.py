from __future__ import annotations

from dataclasses import dataclass


from .class_child import Child


@dataclass
class Parent:
    """Parent references Child."""

    name: str
    children: list[Child] | None = None
