from __future__ import annotations

from aiogram import Router, F
from aiogram.types import CallbackQuery
from app.keyboards import menu_kb

router = Router()

TERMS = (
    "الشروط والأحكام:\n"
    "- منع نشاط غير قانوني\n"
    "- تسليم الجوائز مسؤولية منشئ السحب\n"
    "- حق الحظر\n"
    "- النجوم غير مسترجعة\n"
    "- التبرع اختياري\n"
    "- الاستخدام = موافقة\n"
)

PRIVACY = (
    "الخصوصية:\n"
    "يجمع: user_id, username, language\n"
    "لا مشاركة بيانات\n"
    "لا تخزين بيانات حساسة\n"
    "الاستخدام = موافقة\n"
)

@router.callback_query(F.data == "menu:terms")
async def terms(cb: CallbackQuery):
    await cb.message.edit_text(TERMS, reply_markup=menu_kb())
    await cb.answer()

@router.callback_query(F.data == "menu:privacy")
async def privacy(cb: CallbackQuery):
    await cb.message.edit_text(PRIVACY, reply_markup=menu_kb())
    await cb.answer()
