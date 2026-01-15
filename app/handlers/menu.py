from __future__ import annotations

from aiogram import Router, F
from aiogram.types import CallbackQuery
from aiogram.fsm.context import FSMContext

from app.keyboards import menu_kb, pick_chat_kb
from app.texts import MENU_TEXT, CREATE_PICK_CHAT_TEXT

router = Router()


@router.callback_query(F.data == "menu:home")
async def home(cb: CallbackQuery):
    await cb.message.edit_text(MENU_TEXT, reply_markup=menu_kb())
    await cb.answer()


@router.callback_query(F.data == "menu:create")
async def menu_create(cb: CallbackQuery, state: FSMContext):
    await state.clear()
    await cb.message.edit_text(CREATE_PICK_CHAT_TEXT, reply_markup=pick_chat_kb("create"))
    await cb.answer()


@router.callback_query(F.data == "menu:chlog")
async def menu_chlog(cb: CallbackQuery, state: FSMContext):
    await state.clear()
    await cb.message.edit_text("📂 سجل القناة", reply_markup=pick_chat_kb("chlog"))
    await cb.answer()


@router.callback_query(F.data == "menu:contest:todo")
async def contest_todo(cb: CallbackQuery):
    await cb.answer("ميزة المسابقات مؤجلة في هذا الإصدار.", show_alert=True)
