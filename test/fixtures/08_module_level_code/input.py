"""Module with various module-level code that should NOT be extracted."""

from typing import TypeVar, Generic

# Module-level constant
DEFAULT_TIMEOUT = 30

# TypeVar declaration
T = TypeVar("T")
K = TypeVar("K")
V = TypeVar("V")

# __all__ declaration
__all__ = ["Container", "process_value"]


class Container(Generic[T]):
    """A generic container."""

    def __init__(self, value: T) -> None:
        self.value = value


def process_value(x: T) -> T:
    """Process a value."""
    return x
