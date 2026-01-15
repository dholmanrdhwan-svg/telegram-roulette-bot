from __future__ import annotations

import time
from aiogram.types import InlineKeyboardMarkup, InlineKeyboardButton
from aiogram.utils.keyboard import InlineKeyboardBuilder
from app.config import settings
from app.security import sign_payload


def gate_kb() -> InlineKeyboardMarkup:
    b = InlineKeyboardBuilder()
    if settings.mandatory_channels_list:
        ch = settings.mandatory_channels_list[0]
        url = ch if ch.startswith("http") else f"https://t.me/{ch.lstrip('@')}"
        b.add(InlineKeyboardButton(text="القناة", url=url))
    else:
        b.add(InlineKeyboardButton(text="القناة", callback_data="noop"))
    b.add(InlineKeyboardButton(text="لقد اشتركت", callback_data="gate:check"))
    b.add(InlineKeyboardButton(text="ذكرني إذا فزت", callback_data="notify:toggle"))
    b.adjust(1)
    return b.as_markup()


def menu_kb() -> InlineKeyboardMarkup:
    b = InlineKeyboardBuilder()
    b.button(text="🔄 إنشاء روليت", callback_data="menu:create")
    b.button(text="📂 سجل القناة", callback_data="menu:chlog")
    b.button(text="❤️ التبرع", callback_data="menu:donate")
    b.button(text="📊 الإحصائيات", callback_data="menu:stats")
    b.button(text="📜 الشروط والأحكام", callback_data="menu:terms")
    b.button(text="🔐 الخصوصية", callback_data="menu:privacy")
    b.button(text="🛠️ الدعم الفني", url=f"https://t.me/{settings.support_bot.lstrip('@')}")
    b.button(text="🔔 ذكرني إذا فزت", callback_data="notify:toggle")
    b.button(text="🎯 أنشئ مسابقة", callback_data="menu:contest:todo")
    b.adjust(2)
    return b.as_markup()


def back_kb(cb: str = "menu:home") -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(text="رجوع", callback_data=cb)]])


def pick_chat_kb(prefix: str) -> InlineKeyboardMarkup:
    b = InlineKeyboardBuilder()
    b.button(text="✏️ تسجيل القناة", callback_data=f"{prefix}:reg:channel")
    b.button(text="✏️ تسجيل قروب", callback_data=f"{prefix}:reg:group")
    b.button(text="رجوع", callback_data="menu:home")
    b.adjust(1)
    return b.as_markup()


def conditions_kb() -> InlineKeyboardMarkup:
    b = InlineKeyboardBuilder()
    b.button(text="قناة الشرط", callback_data="cond:channel")
    b.button(text="تصويت متسابق", callback_data="cond:contest:todo")
    b.button(text="تعزيز قناة", callback_data="cond:boost:todo")
    b.button(text="تعليق على منشور (مدفوع)", callback_data="cond:comment:paid")
    b.button(text="تخطي", callback_data="cond:skip")
    b.button(text="رجوع", callback_data="create:back:template")
    b.adjust(1)
    return b.as_markup()


def yes_no_kb(yes_cb: str, no_cb: str) -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(inline_keyboard=[
        [
            InlineKeyboardButton(text="نعم", callback_data=yes_cb),
            InlineKeyboardButton(text="لا", callback_data=no_cb),
        ]
    ])


def auto_draw_type_kb() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="السحب عند وصول المشتركين/المشاركين لعدد معين", callback_data="autodraw:type:entries")],
        [InlineKeyboardButton(text="رجوع", callback_data="create:back:autodraw")],
    ])


def participate_button(giveaway_id: int) -> InlineKeyboardMarkup:
    payload = {"g": giveaway_id, "ts": int(time.time()), "n": "p"}
    token = sign_payload(payload)
    return InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="مشاركة", callback_data=f"p:{token}")]
    ])


def entry_admin_kb(user_id: int, entry_id: int) -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(inline_keyboard=[
        [
            InlineKeyboardButton(text="👤 عرض الملف الشخصي", url=f"tg://user?id={user_id}"),
            InlineKeyboardButton(text="❌ استبعاد", callback_data=f"entry:exclude:{entry_id}"),
        ]
    ])
