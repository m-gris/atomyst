import logging
from typing import Optional


logger = logging.getLogger(__name__)


class ResponseBuilder:
    """Builds responses."""

    def build(self, data: str) -> str:
        logger.info(f"Building response for: {data}")
        return f"Response: {data}"
