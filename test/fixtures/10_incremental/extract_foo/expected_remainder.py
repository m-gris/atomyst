"""Module with multiple classes for incremental extraction."""

from dataclasses import dataclass




@dataclass
class Bar:
    """Second class."""

    y: str


@dataclass
class Baz:
    """Third class."""

    z: float
