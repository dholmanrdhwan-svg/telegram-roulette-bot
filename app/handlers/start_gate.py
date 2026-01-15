from __future__ import annotations

from aiogram import Router, Bot, F
from aiogram.types import Message, CallbackQuery
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import User
from app.keyboards import gate_kb, menu_kb
from app.texts import GATE_TEXT, MENU_TEXT, POPUP_ENABLED_NOTIFY, NOTIFY_INFO
from app.config import settings

router = Router()


async def upsert_user(session: AsyncSession, tg_user) -> User:
    u = await session.get(User, tg_user.id)
    if not u:
        u = User(
            id=tg_user.id,
            username=tg_user.username,
            language=tg_user.language_code,
        )
        session.add(u)
        await session.commit()
        await session.refresh(u)
    else:
        changed = False
        if u.username != tg_user.username:
            u.username = tg_user.username
            changed = True
        if u.language != tg_user.language_code:
            u.language = tg_user.language_code
            changed = True
        if changed:
            await session.commit()
    return u


async def user_in_all_mandatory(bot: Bot, user_id: int) -> bool:
    if not settings.mandatory_channels_list:
        return True

    for ch in settings.mandatory_channels_list:
        try:
            if ch.startswith("@"):
                chat = await bot.get_chat(ch)
            elif "t.me/" in ch:
                username = ch.split("t.me/")[-1].split("?")[0].strip("/")
                chat = await bot.get_chat(f"@{username}")
            else:
                return False
            cm = await bot.get_chat_member(chat.id, user_id)
            if cm.status in ("left", "kicked"):
                return False
        except Exception:
            return False
    return True


@router.message(F.text == "/start")
async def start_cmd(message: Message, bot: Bot, session: AsyncSession):
    u = await upsert_user(session, message.from_user)
    if u.is_banned:
        return

    if u.gate_verified and not u.suspended:
        await message.answer(MENU_TEXT, reply_markup=menu_kb())
        return

    await message.answer(GATE_TEXT, reply_markup=gate_kb())


@router.callback_query(F.data == "gate:check")
async def gate_check(cb: CallbackQuery, bot: Bot, session: AsyncSession):
    u = await upsert_user(session, cb.from_user)
    if u.is_banned:
        await cb.answer("موقوف.", show_alert=True)
        return

    ok = await user_in_all_mandatory(bot, u.id)
    if not ok:
        await cb.answer("لم يتم العثور على اشتراكك في القنوات الإلزامية.", show_alert=True)
        return

    u.gate_verified = True
    u.suspended = False
    await session.commit()

    await cb.message.edit_text(MENU_TEXT, reply_markup=menu_kb())
    await cb.answer("تم التحقق بنجاح.", show_alert=False)


@router.callback_query(F.data == "notify:toggle")
async def toggle_notify(cb: CallbackQuery, session: AsyncSession):
    u = await upsert_user(session, cb.from_user)
    if u.is_banned:
        await cb.answer("موقوف.", show_alert=True)
        return
    u.notify_on_win = True
    await session.commit()
    await cb.answer(POPUP_ENABLED_NOTIFY, show_alert=True)
    try:
        await cb.message.answer(NOTIFY_INFO)
    except Exception:
        pass


@router.callback_query(F.data == "noop")
async def noop(cb: CallbackQuery):
    await cb.answer("…", show_alert=False)
