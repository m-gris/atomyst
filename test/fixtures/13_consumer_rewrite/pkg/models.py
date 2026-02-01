"""Module that re-exports some things."""

from typing import Optional
from dataclasses import dataclass


@dataclass
class Query:
    """A query model."""
    text: str
    limit: Optional[int] = None


@dataclass
class Response:
    """A response model."""
    data: str
