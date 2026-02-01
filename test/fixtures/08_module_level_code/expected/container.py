from typing import Generic



class Container(Generic[T]):
    """A generic container."""

    def __init__(self, value: T) -> None:
        self.value = value
