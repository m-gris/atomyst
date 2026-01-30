"""Module with various module-level code that should NOT be extracted."""
from typing import TypeVar, Generic



class Container(Generic[T]):
    """A generic container."""

    def __init__(self, value: T) -> None:
        self.value = value
