from __future__ import annotations

from aiogram import Router, F
from aiogram.types import CallbackQuery
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Entry, AuditLog

router = Router()


async def audit(session: AsyncSession, actor: int | None, action: str, entity: str, entity_id: str | None, detail: str | None):
    session.add(AuditLog(actor_user_id=actor, action=action, entity=entity, entity_id=entity_id, detail=detail))


@router.callback_query(F.data.startswith("entry:exclude:"))
async def exclude_entry(cb: CallbackQuery, session: AsyncSession):
    try:
        entry_id = int(cb.data.split("entry:exclude:", 1)[1])
    except Exception:
        await cb.answer("خطأ.", show_alert=True)
        return

    e = await session.get(Entry, entry_id)
    if not e:
        await cb.answer("غير موجود.", show_alert=True)
        return

    if not e.excluded:
        e.excluded = True
        await audit(session, cb.from_user.id, "exclude", "entry", str(entry_id), None)
        await session.commit()

    await cb.answer("تم استبعاده", show_alert=True)
