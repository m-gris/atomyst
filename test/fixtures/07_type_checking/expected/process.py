"""Module demonstrating TYPE_CHECKING imports."""
from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING



def process(item: AnotherType) -> str:
    """Function using TYPE_CHECKING import."""
    return str(item)
