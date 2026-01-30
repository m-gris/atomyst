"""Module with async functions."""
import asyncio
from typing import Any




async def fetch_data(url: str) -> dict[str, Any]:
    """Fetch data from URL."""
    await asyncio.sleep(0.1)
    return {"url": url}
