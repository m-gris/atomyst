from typing import Dict

from ._constants import SQL_TYPE_MAPPING, DEFAULT_LIMIT


class Query:
    """A query class that uses module constants."""

    def get_sql_type(self, py_type: str) -> str:
        return SQL_TYPE_MAPPING.get(py_type, "unknown")

    def get_limit(self) -> int:
        return DEFAULT_LIMIT
