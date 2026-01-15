from __future__ import annotations

from aiogram import Router, Bot, F
from aiogram.types import CallbackQuery, Message
from aiogram.fsm.state import State, StatesGroup
from aiogram.fsm.context import FSMContext
from sqlalchemy.ext.asyncio import AsyncSession
from aiogram.exceptions import TelegramBadRequest

from app.keyboards import pick_chat_kb, back_kb, menu_kb
from app.texts import CHANNEL_LOG_ENTRY_TEXT, REGISTER_CHAT_INSTRUCTIONS
from app.utils import extract_forwarded_chat_id, ensure_bot_admin
from app.models import ChannelLog

router = Router()


class ChannelLogFlow(StatesGroup):
    waiting_forward_source = State()
    waiting_forward_logchat = State()


@router.callback_query(F.data == "menu:chlog")
async def show_chlog_menu(cb: CallbackQuery):
    await cb.message.edit_text(CHANNEL_LOG_ENTRY_TEXT, reply_markup=pick_chat_kb("chlog"))
    await cb.answer()


@router.callback_query(F.data.in_({"chlog:reg:channel", "chlog:reg:group"}))
async def chlog_register_source(cb: CallbackQuery, state: FSMContext):
    await state.set_state(ChannelLogFlow.waiting_forward_source)
    await cb.message.edit_text(REGISTER_CHAT_INSTRUCTIONS, reply_markup=back_kb("menu:chlog"))
    await cb.answer()


@router.message(ChannelLogFlow.waiting_forward_source)
async def on_forward_source(message: Message, bot: Bot, session: AsyncSession, state: FSMContext):
    source_chat_id = extract_forwarded_chat_id(message)
    if not source_chat_id:
        await message.answer("أعد توجيه رسالة من القناة/القروب.")
        return

    ok, err = await ensure_bot_admin(bot, source_chat_id)
    if not ok:
        await message.answer(err)
        return

    try:
        cm = await bot.get_chat_member(source_chat_id, message.from_user.id)
        if cm.status != "creator":
            await message.answer("يجب أن تكون مالك القناة (Creator) لربطها كسجل.")
            return
    except TelegramBadRequest:
        await message.answer("تعذر التحقق من ملكيتك للقناة.")
        return

    await state.update_data(source_chat_id=source_chat_id)
    await state.set_state(ChannelLogFlow.waiting_forward_logchat)
    await message.answer("الآن أعد توجيه رسالة من قناة أخرى لتكون “قناة السجل” (يفضّل قناة خاصة).", reply_markup=back_kb("menu:chlog"))


@router.message(ChannelLogFlow.waiting_forward_logchat)
async def on_forward_logchat(message: Message, bot: Bot, session: AsyncSession, state: FSMContext):
    log_chat_id = extract_forwarded_chat_id(message)
    if not log_chat_id:
        await message.answer("أعد توجيه رسالة من قناة السجل.")
        return

    ok, err = await ensure_bot_admin(bot, log_chat_id)
    if not ok:
        await message.answer(err)
        return

    data = await state.get_data()
    source_chat_id = data["source_chat_id"]

    chlog = ChannelLog(
        source_chat_id=source_chat_id,
        owner_user_id=message.from_user.id,
        log_chat_id=log_chat_id,
    )
    await session.merge(chlog)
    await session.commit()

    await message.answer("تم اختيار قناة السجل بنجاح", reply_markup=menu_kb())
    await state.clear()
