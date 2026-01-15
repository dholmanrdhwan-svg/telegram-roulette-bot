from __future__ import annotations

from aiogram import Router, F
from aiogram.types import CallbackQuery
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, desc

from app.models import Entry, Giveaway
from app.keyboards import menu_kb

router = Router()


@router.callback_query(F.data == "menu:stats")
async def stats(cb: CallbackQuery, session: AsyncSession):
    q1 = await session.execute(
        select(func.count(Entry.id))
        .join(Giveaway, Giveaway.id == Entry.giveaway_id)
        .where(Entry.user_id == cb.from_user.id, Giveaway.is_drawn == False)
    )
    current = q1.scalar_one()

    q2 = await session.execute(
        select(Giveaway.target_chat_id, func.count(Entry.id).label("cnt"))
        .join(Entry, Entry.giveaway_id == Giveaway.id)
        .group_by(Giveaway.target_chat_id)
        .order_by(desc("cnt"))
        .limit(10)
    )
    top = q2.all()

    text = f"عدد السحوبات التي أنا مشترك فيها حاليًا: {current}\n\nأفضل 10 قنوات (حسب عدد المشاركات داخل البوت):\n"
    for chat_id, cnt in top:
        text += f"- {chat_id}: اشتراك {cnt}\n"

    await cb.message.edit_text(text, reply_markup=menu_kb())
    await cb.answer()
