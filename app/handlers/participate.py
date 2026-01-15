from __future__ import annotations

import time
from aiogram import Router, Bot, F
from aiogram.types import CallbackQuery
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func

from app.security import verify_payload
from app.models import Giveaway, Entry, User, ChannelLog, AuditLog
from app.keyboards import entry_admin_kb
from app.texts import LOG_ENTRY_NEW

router = Router()

_last_click = {}  # (user_id, giveaway_id) -> ts


async def audit(session: AsyncSession, actor: int | None, action: str, entity: str, entity_id: str | None, detail: str | None):
    session.add(AuditLog(actor_user_id=actor, action=action, entity=entity, entity_id=entity_id, detail=detail))


async def check_user_gate(session: AsyncSession, user_id: int) -> bool:
    u = await session.get(User, user_id)
    if not u or u.is_banned:
        return False
    if not u.gate_verified or u.suspended:
        return False
    return True


async def conditions_ok(bot: Bot, g: Giveaway, cb: CallbackQuery) -> tuple[bool, str]:
    if g.premium_only and not (cb.from_user.is_premium is True):
        return False, "هذا السحب متاح فقط لمستخدمي Telegram Premium."

    for cond in (g.cond_channel_1, g.cond_channel_2):
        if cond:
            try:
                cm = await bot.get_chat_member(cond, cb.from_user.id)
                if cm.status in ("left", "kicked"):
                    return False, "يجب استيفاء شروط الاشتراك في قناة الشرط."
            except Exception:
                return False, "تعذر التحقق من شروط القناة الآن."

    if g.paid_comment_condition_enabled:
        return False, "شرط التعليق مفعل لكن لا يوجد تحقق رسمي مطبق في هذا الإصدار."

    return True, ""


@router.callback_query(F.data.startswith("p:"))
async def participate(cb: CallbackQuery, bot: Bot, session: AsyncSession):
    token = cb.data.split("p:", 1)[1]
    data = verify_payload(token)
    if not data:
        await cb.answer("رابط مشاركة غير صالح.", show_alert=True)
        return

    giveaway_id = int(data["g"])
    now = time.time()
    key = (cb.from_user.id, giveaway_id)
    if now - _last_click.get(key, 0) < 2.0:
        await cb.answer("تمهل قليلًا.", show_alert=False)
        return
    _last_click[key] = now

    if not await check_user_gate(session, cb.from_user.id):
        await cb.answer("يجب إتمام بوابة الاشتراك أولًا.", show_alert=True)
        return

    g = await session.get(Giveaway, giveaway_id)
    if not g:
        await cb.answer("السحب غير موجود.", show_alert=True)
        return
    if g.is_drawn:
        await cb.answer("انتهى السحب.", show_alert=True)
        return

    ok, err = await conditions_ok(bot, g, cb)
    if not ok:
        await cb.answer(err, show_alert=True)
        return

    seq_no = (await session.execute(
        select(func.count(Entry.id)).where(Entry.giveaway_id == g.id)
    )).scalar_one() + 1

    e = Entry(
        giveaway_id=g.id,
        user_id=cb.from_user.id,
        username=cb.from_user.username,
        seq_no=seq_no,
        excluded=False,
    )
    session.add(e)
    try:
        await session.commit()
    except Exception:
        await session.rollback()
        await cb.answer("أنت مشارك بالفعل.", show_alert=True)
        return

    await audit(session, cb.from_user.id, "entry_create", "giveaway", str(g.id), f"seq={seq_no}")
    await session.commit()

    await cb.answer("تمت المشاركة.", show_alert=False)

    chlog = await session.get(ChannelLog, g.target_chat_id)
    if chlog:
        text = (
            f"{LOG_ENTRY_NEW}\n"
            f"{('@' + cb.from_user.username) if cb.from_user.username else 'بدون يوزر'}\n"
            f"{cb.from_user.id}\n"
            f"{int(time.time())}\n"
            f"عدد المشاركين: {seq_no}"
        )
        try:
            await bot.send_message(
                chat_id=chlog.log_chat_id,
                text=text,
                reply_markup=entry_admin_kb(cb.from_user.id, e.id),
            )
        except Exception:
            pass
