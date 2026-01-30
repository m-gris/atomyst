"""Module with async functions."""
import asyncio
from typing import Any




async def process_items(items: list[str]) -> list[str]:
    """Process items concurrently."""
    return [item.upper() for item in items]
