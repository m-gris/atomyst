import functools
from dataclasses import dataclass, field
from typing import Callable, TypeVar

from .def_log_calls import log_calls


@log_calls
@functools.lru_cache(maxsize=128)
def expensive_computation(n: int) -> int:
    """A cached, logged function."""
    return sum(range(n))
