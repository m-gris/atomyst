from dataclasses import dataclass




@dataclass
class Person:
    """A person with a name and age."""

    name: str
    age: int

    def greet(self) -> str:
        return f"Hello, I'm {self.name}"
