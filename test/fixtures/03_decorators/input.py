"""Module demonstrating decorator handling."""

import functools
from dataclasses import dataclass, field
from typing import Callable, TypeVar

T = TypeVar("T")


def log_calls(func: Callable[..., T]) -> Callable[..., T]:
    """Decorator that logs function calls."""

    @functools.wraps(func)
    def wrapper(*args, **kwargs):
        print(f"Calling {func.__name__}")
        return func(*args, **kwargs)

    return wrapper


@dataclass
@functools.total_ordering
class Priority:
    """A priority value with comparison support."""

    value: int
    label: str = ""

    def __lt__(self, other: "Priority") -> bool:
        return self.value < other.value


@log_calls
@functools.lru_cache(maxsize=128)
def expensive_computation(n: int) -> int:
    """A cached, logged function."""
    return sum(range(n))
