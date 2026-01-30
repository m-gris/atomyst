"""Module demonstrating comment handling."""

from dataclasses import dataclass


# This comment is directly above the class
# It should be included with the class
class WithComment:
    """Class with preceding comments."""

    pass


# This comment has a blank line below

class WithBlankLine:
    """Class with blank line after comment - comment stays orphaned."""

    pass


class NoComment:
    """Class with no preceding comment."""

    pass
