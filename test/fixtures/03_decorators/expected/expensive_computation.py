"""Module demonstrating decorator handling."""

import functools
from dataclasses import dataclass, field
from typing import Callable, TypeVar

T = TypeVar("T")


@log_calls
@functools.lru_cache(maxsize=128)
def expensive_computation(n: int) -> int:
    """A cached, logged function."""
    return sum(range(n))
