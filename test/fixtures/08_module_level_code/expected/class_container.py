from typing import TypeVar, Generic

from ._constants import T


class Container(Generic[T]):
    """A generic container."""

    def __init__(self, value: T) -> None:
        self.value = value
