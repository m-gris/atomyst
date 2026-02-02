"""Test: constants that reference sibling definitions need prefixed imports."""


def _hacky_features_handler():
    """A handler function referenced by a constant."""
    return "handled"


# This constant references the function above
# _constants.py must import it with the kind prefix
HANDLER = _hacky_features_handler
