"""Module with async functions."""
import asyncio
from typing import Any




class AsyncClient:
    """A client with async methods."""

    async def connect(self) -> None:
        """Connect to server."""
        await asyncio.sleep(0.1)

    async def disconnect(self) -> None:
        """Disconnect from server."""
        pass
