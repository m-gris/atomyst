import functools
from typing import Callable



def log_calls(func: Callable[..., T]) -> Callable[..., T]:
    """Decorator that logs function calls."""

    @functools.wraps(func)
    def wrapper(*args, **kwargs):
        print(f"Calling {func.__name__}")
        return func(*args, **kwargs)

    return wrapper
