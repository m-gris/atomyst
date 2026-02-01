"""Test: constants that reference sibling definitions."""


def handler_a():
    return "A"


def handler_b():
    return "B"


HANDLERS = [handler_a, handler_b]


class Dispatcher:
    """Uses the handlers list."""

    def dispatch(self, idx: int):
        return HANDLERS[idx]()
