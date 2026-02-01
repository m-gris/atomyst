"""Test file with module-level constants."""

from typing import Dict

SQL_TYPE_MAPPING: Dict[str, str] = {"str": "text", "int": "integer"}

DEFAULT_LIMIT = 100


class Query:
    """A query class that uses module constants."""

    def get_sql_type(self, py_type: str) -> str:
        return SQL_TYPE_MAPPING.get(py_type, "unknown")

    def get_limit(self) -> int:
        return DEFAULT_LIMIT


class Response:
    """A response class that does NOT use constants."""

    def __init__(self, data: str):
        self.data = data
