"""Database operations for xray-bot."""

import asyncpg


async def get_pool(database_url: str) -> asyncpg.Pool:
    """Create a connection pool."""
    return await asyncpg.create_pool(database_url, min_size=1, max_size=5)


async def sync_clients(pool: asyncpg.Pool, clients: list[dict]) -> None:
    """Sync VLESS clients from Xray config into the database.

    Inserts new UUIDs, updates email for existing ones.
    Does NOT remove UUIDs that are no longer in config (they may still
    be bound to users).
    """
    async with pool.acquire() as conn:
        for client in clients:
            await conn.execute(
                """
                INSERT INTO xray_client (uuid, email)
                VALUES ($1, $2)
                ON CONFLICT (uuid) DO UPDATE SET email = $2
                """,
                client["uuid"],
                client["email"],
            )


async def ensure_telegram_user(
    pool: asyncpg.Pool,
    telegram_id: int,
    username: str | None,
    first_name: str | None,
) -> None:
    """Register or update a Telegram user."""
    async with pool.acquire() as conn:
        await conn.execute(
            """
            INSERT INTO telegram_user (telegram_id, username, first_name)
            VALUES ($1, $2, $3)
            ON CONFLICT (telegram_id) DO UPDATE
              SET username = $2, first_name = $3
            """,
            telegram_id,
            username,
            first_name,
        )


async def get_user_uuids(pool: asyncpg.Pool, telegram_id: int) -> list[dict]:
    """Get all UUIDs bound to a Telegram user."""
    async with pool.acquire() as conn:
        rows = await conn.fetch(
            """
            SELECT c.uuid, c.email
            FROM user_uuid u
            JOIN xray_client c ON c.uuid = u.uuid
            WHERE u.telegram_id = $1
            ORDER BY u.bound_at
            """,
            telegram_id,
        )
        return [dict(r) for r in rows]


async def get_all_clients(pool: asyncpg.Pool) -> list[dict]:
    """Get all known VLESS clients."""
    async with pool.acquire() as conn:
        rows = await conn.fetch(
            "SELECT uuid, email FROM xray_client ORDER BY discovered"
        )
        return [dict(r) for r in rows]
