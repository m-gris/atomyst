"""Test: definitions that reference sibling definitions need prefixed imports."""


class SlotMatchResult:
    """A data class referenced by a function."""
    def __init__(self, matched: bool):
        self.matched = matched


def process_slot(data) -> SlotMatchResult:
    """Function that returns a sibling class - needs import with prefix."""
    return SlotMatchResult(matched=True)
