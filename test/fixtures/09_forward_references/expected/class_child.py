from __future__ import annotations

from dataclasses import dataclass


from .class_parent import Parent


@dataclass
class Child:
    """Child references Parent."""

    name: str
    parent: Parent | None = None
