from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from another_module import AnotherType




def process(item: AnotherType) -> str:
    """Function using TYPE_CHECKING import."""
    return str(item)
