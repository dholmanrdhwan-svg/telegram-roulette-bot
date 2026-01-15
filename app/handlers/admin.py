from __future__ import annotations

from aiogram import Router, F
from aiogram.types import Message
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models import User, Chat, AuditLog

router = Router()


def is_admin(user_id: int) -> bool:
    return user_id in settings.admin_ids_list


async def audit(session: AsyncSession, actor: int | None, action: str, entity: str, entity_id: str | None, detail: str | None):
    session.add(AuditLog(actor_user_id=actor, action=action, entity=entity, entity_id=entity_id, detail=detail))


@router.message(F.text.startswith("/ban_user"))
async def ban_user(message: Message, session: AsyncSession):
    if not is_admin(message.from_user.id):
        return
    parts = (message.text or "").split()
    if len(parts) != 2:
        await message.answer("استخدم: /ban_user <user_id>")
        return
    uid = int(parts[1])
    u = await session.get(User, uid)
    if not u:
        await message.answer("غير موجود.")
        return
    u.is_banned = True
    await audit(session, message.from_user.id, "ban_user", "user", str(uid), None)
    await session.commit()
    await message.answer("تم حظر المستخدم.")


@router.message(F.text.startswith("/ban_chat"))
async def ban_chat(message: Message, session: AsyncSession):
    if not is_admin(message.from_user.id):
        return
    parts = (message.text or "").split()
    if len(parts) != 2:
        await message.answer("استخدم: /ban_chat <chat_id>")
        return
    cid = int(parts[1])
    c = await session.get(Chat, cid)
    if not c:
        c = Chat(id=cid, type="unknown", title=None, username=None, is_banned=True)
        session.add(c)
    else:
        c.is_banned = True
    await audit(session, message.from_user.id, "ban_chat", "chat", str(cid), None)
    await session.commit()
    await message.answer("تم حظر القناة/القروب.")
