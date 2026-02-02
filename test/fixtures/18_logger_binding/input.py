"""Module with logger binding that depends on __name__."""
import logging
from typing import Optional

logger = logging.getLogger(__name__)

TIMEOUT = 30


class QueryHandler:
    """Handles queries with logging."""

    def __init__(self, name: str):
        self.name = name
        logger.info(f"Created QueryHandler: {name}")

    def execute(self, query: str) -> Optional[str]:
        logger.debug(f"Executing query: {query}")
        return query.upper()


class ResponseBuilder:
    """Builds responses."""

    def build(self, data: str) -> str:
        logger.info(f"Building response for: {data}")
        return f"Response: {data}"
