import asyncpg
import os
from typing import Optional

_pool: Optional[asyncpg.Pool] = None


async def get_pool() -> asyncpg.Pool:
    """Returns the connection pool. Must be initialised via init_pool() first."""
    if _pool is None:
        raise RuntimeError(
            "Database pool has not been initialised. "
            "Ensure init_pool() is called in the FastAPI lifespan handler."
        )
    return _pool


# Alias used by app.py for direct queries (e.g. GET /session/{id})
# so callers don't have to import through the repository layer.
get_pool_direct = get_pool


async def init_pool() -> None:
    """Create the connection pool. Call once at application startup."""
    global _pool
    _pool = await asyncpg.create_pool(
        dsn=os.environ["DATABASE_URL"],
        min_size=2,
        max_size=10,
        command_timeout=30,
    )


async def close_pool() -> None:
    global _pool
    if _pool:
        await _pool.close()
        _pool = None