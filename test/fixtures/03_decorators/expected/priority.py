"""Module demonstrating decorator handling."""

import functools
from dataclasses import dataclass, field
from typing import Callable, TypeVar

T = TypeVar("T")


@dataclass
@functools.total_ordering
class Priority:
    """A priority value with comparison support."""

    value: int
    label: str = ""

    def __lt__(self, other: "Priority") -> bool:
        return self.value < other.value
