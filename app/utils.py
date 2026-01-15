from __future__ import annotations

from aiogram import Bot
from aiogram.types import Message
from aiogram.exceptions import TelegramBadRequest
from typing import Optional, Tuple


def extract_forwarded_chat_id(msg: Message) -> Optional[int]:
    try:
        if msg.forward_origin and getattr(msg.forward_origin, "type", None) == "chat":
            chat = getattr(msg.forward_origin, "chat", None)
            if chat:
                return chat.id
    except Exception:
        pass

    if msg.forward_from_chat:
        return msg.forward_from_chat.id

    return None


async def ensure_bot_admin(bot: Bot, chat_id: int) -> Tuple[bool, str]:
    try:
        me = await bot.get_me()
        cm = await bot.get_chat_member(chat_id, me.id)
        if cm.status not in ("administrator", "creator"):
            return False, "يجب إضافة البوت مشرفًا في هذه الجهة."
        return True, ""
    except TelegramBadRequest:
        return False, "تعذر التحقق. تأكد من أن البوت مضاف."
    except Exception:
        return False, "خطأ غير متوقع أثناء التحقق."


async def ensure_bot_admin_with_member_mgmt(bot: Bot, chat_id: int) -> Tuple[bool, str]:
    try:
        me = await bot.get_me()
        cm = await bot.get_chat_member(chat_id, me.id)
        if cm.status == "creator":
            return True, ""
        if cm.status != "administrator":
            return False, "يجب إضافة البوت مشرفًا في قناة الشرط."
        can_restrict = getattr(cm, "can_restrict_members", False)
        if not can_restrict:
            return False, "يجب منح البوت صلاحية إدارة الأعضاء في قناة الشرط."
        return True, ""
    except Exception:
        return False, "تعذر التحقق من صلاحيات البوت في قناة الشرط."
