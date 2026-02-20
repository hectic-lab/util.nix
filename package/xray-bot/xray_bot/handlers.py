"""Telegram bot handlers for xray-bot."""

import logging

from aiogram import Router, F
from aiogram.filters import CommandStart, Command
from aiogram.types import (
    Message,
    CallbackQuery,
    InlineKeyboardButton,
    InlineKeyboardMarkup,
)

from .config import VlessServerParams
from .db import ensure_telegram_user, get_user_uuids
from .vless import generate_vless_link

log = logging.getLogger(__name__)
router = Router()


def make_keys_keyboard(uuids: list[dict]) -> InlineKeyboardMarkup:
    """Build inline keyboard with one button per UUID."""
    buttons = []
    for entry in uuids:
        label = entry.get("email") or entry["uuid"][:8]
        buttons.append([
            InlineKeyboardButton(
                text=f"🔑 {label}",
                callback_data=f"uuid:{entry['uuid']}",
            )
        ])
    if not buttons:
        buttons.append([
            InlineKeyboardButton(
                text="No keys assigned",
                callback_data="noop",
            )
        ])
    return InlineKeyboardMarkup(inline_keyboard=buttons)


def make_servers_keyboard(
    uuid: str, servers: list[VlessServerParams],
) -> InlineKeyboardMarkup:
    """Build inline keyboard with one button per server for a given UUID."""
    buttons = []
    for srv in servers:
        buttons.append([
            InlineKeyboardButton(
                text=f"🌐 {srv.name}",
                callback_data=f"link:{srv.name}:{uuid}",
            )
        ])
    buttons.append([
        InlineKeyboardButton(text="« Back", callback_data="back:keys")
    ])
    return InlineKeyboardMarkup(inline_keyboard=buttons)


@router.message(CommandStart())
async def cmd_start(message: Message, pool, servers) -> None:
    """Handle /start -- register user and show their keys."""
    user = message.from_user
    if not user:
        return

    await ensure_telegram_user(pool, user.id, user.username, user.first_name)
    uuids = await get_user_uuids(pool, user.id)

    if uuids:
        text = "Your Xray keys. Tap one to choose a server:"
        kb = make_keys_keyboard(uuids)
        await message.answer(text, reply_markup=kb)
    else:
        await message.answer(
            "You have no keys assigned yet.\n"
            "Contact the admin to get access."
        )


@router.message(Command("mykeys"))
async def cmd_mykeys(message: Message, pool, servers) -> None:
    """Handle /mykeys -- list user's UUIDs with buttons."""
    user = message.from_user
    if not user:
        return

    await ensure_telegram_user(pool, user.id, user.username, user.first_name)
    uuids = await get_user_uuids(pool, user.id)

    if uuids:
        kb = make_keys_keyboard(uuids)
        await message.answer("Your keys:", reply_markup=kb)
    else:
        await message.answer("No keys assigned. Contact the admin.")


@router.callback_query(F.data.startswith("uuid:"))
async def cb_select_uuid(
    callback: CallbackQuery, pool, servers: list[VlessServerParams],
) -> None:
    """Handle UUID button -- show server selection."""
    if not callback.data or not callback.from_user:
        return

    uuid = callback.data.removeprefix("uuid:")
    user = callback.from_user

    uuids = await get_user_uuids(pool, user.id)
    owned = any(u["uuid"] == uuid for u in uuids)
    if not owned:
        await callback.answer("This key is not assigned to you.", show_alert=True)
        return

    email = next((u["email"] for u in uuids if u["uuid"] == uuid), "")
    label = email or uuid[:8]

    kb = make_servers_keyboard(uuid, servers)
    await callback.message.edit_text(
        f"Key: <b>{label}</b>\n\nChoose a server:",
        reply_markup=kb,
        parse_mode="HTML",
    )
    await callback.answer()


@router.callback_query(F.data.startswith("link:"))
async def cb_generate_link(
    callback: CallbackQuery, pool, servers: list[VlessServerParams],
) -> None:
    """Handle server button -- generate and send VLESS link."""
    if not callback.data or not callback.from_user:
        return

    # callback_data = "link:<server_name>:<uuid>"
    parts = callback.data.removeprefix("link:").split(":", 1)
    if len(parts) != 2:
        await callback.answer("Invalid request.", show_alert=True)
        return

    server_name, uuid = parts
    user = callback.from_user

    uuids = await get_user_uuids(pool, user.id)
    owned = any(u["uuid"] == uuid for u in uuids)
    if not owned:
        await callback.answer("This key is not assigned to you.", show_alert=True)
        return

    server = next((s for s in servers if s.name == server_name), None)
    if server is None:
        await callback.answer("Unknown server.", show_alert=True)
        return

    email = next((u["email"] for u in uuids if u["uuid"] == uuid), "")
    remark = f"{server.name}-{email}" if email else f"{server.name}-{uuid[:8]}"
    link = generate_vless_link(uuid, server, remark=remark)

    await callback.message.answer(
        f"<b>{server.name}</b> connection link:\n\n"
        f"<code>{link}</code>\n\n"
        f"Copy and paste into Happ (or any VLESS-compatible client).",
        parse_mode="HTML",
    )
    await callback.answer()


@router.callback_query(F.data == "back:keys")
async def cb_back_to_keys(callback: CallbackQuery, pool, servers) -> None:
    """Handle back button -- return to key list."""
    if not callback.from_user:
        return

    user = callback.from_user
    uuids = await get_user_uuids(pool, user.id)
    kb = make_keys_keyboard(uuids)
    await callback.message.edit_text("Your keys:", reply_markup=kb)
    await callback.answer()


@router.callback_query(F.data == "noop")
async def cb_noop(callback: CallbackQuery) -> None:
    """Handle noop button."""
    await callback.answer()
