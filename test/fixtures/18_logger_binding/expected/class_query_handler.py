import logging
from typing import Optional


logger = logging.getLogger(__name__)


class QueryHandler:
    """Handles queries with logging."""

    def __init__(self, name: str):
        self.name = name
        logger.info(f"Created QueryHandler: {name}")

    def execute(self, query: str) -> Optional[str]:
        logger.debug(f"Executing query: {query}")
        return query.upper()
