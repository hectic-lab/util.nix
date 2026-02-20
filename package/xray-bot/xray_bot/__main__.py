"""xray-bot entry point."""

import asyncio
import logging
import os
import sys

from aiogram import Bot, Dispatcher

from .config import parse_xray_config, build_servers
from .db import get_pool, sync_clients
from .handlers import router

log = logging.getLogger(__name__)


def require_env(name: str) -> str:
    """Get a required environment variable or exit."""
    val = os.environ.get(name)
    if not val:
        log.error("Missing required environment variable: %s", name)
        sys.exit(3)
    return val


async def run() -> None:
    """Main async entry point."""
    logging.basicConfig(
        level=os.environ.get("LOG_LEVEL", "INFO").upper(),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )

    bot_token = require_env("BOT_TOKEN")
    database_url = require_env("DATABASE_URL")
    xray_config_path = require_env("XRAY_CONFIG_PATH")
    servers_json = require_env("XRAY_SERVERS")

    log.info("Parsing Xray config from %s", xray_config_path)
    xray_config = parse_xray_config(xray_config_path)
    log.info(
        "Found %d clients, stream: %s/%s",
        len(xray_config.clients),
        xray_config.stream.security,
        xray_config.stream.network,
    )

    servers = build_servers(servers_json, xray_config.stream)
    log.info("Loaded %d server endpoints: %s",
             len(servers), ", ".join(s.name for s in servers))

    log.info("Connecting to database")
    pool = await get_pool(database_url)

    log.info("Syncing clients to database")
    clients = [
        {"uuid": c.uuid, "email": c.email} for c in xray_config.clients
    ]
    await sync_clients(pool, clients)
    log.info("Synced %d clients", len(clients))

    bot = Bot(token=bot_token)
    dp = Dispatcher()
    dp.include_router(router)

    # Inject dependencies into handler kwargs
    dp["pool"] = pool
    dp["servers"] = servers

    log.info("Starting bot polling")
    try:
        await dp.start_polling(bot)
    finally:
        await pool.close()


def main() -> None:
    """Sync wrapper for async entry point."""
    asyncio.run(run())
