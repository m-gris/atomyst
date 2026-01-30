"""Module with async functions."""

import asyncio
from typing import Any


async def fetch_data(url: str) -> dict[str, Any]:
    """Fetch data from URL."""
    await asyncio.sleep(0.1)
    return {"url": url}


async def process_items(items: list[str]) -> list[str]:
    """Process items concurrently."""
    return [item.upper() for item in items]


class AsyncClient:
    """A client with async methods."""

    async def connect(self) -> None:
        """Connect to server."""
        await asyncio.sleep(0.1)

    async def disconnect(self) -> None:
        """Disconnect from server."""
        pass
