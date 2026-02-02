from dataclasses import dataclass
from typing import Any




@dataclass
class UserProfile:
    """A user profile."""
    name: str
    email: str
