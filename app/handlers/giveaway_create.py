from __future__ import annotations

import re
from typing import List

from aiogram import Router, Bot, F
from aiogram.types import CallbackQuery, Message
from aiogram.fsm.state import State, StatesGroup
from aiogram.fsm.context import FSMContext
from sqlalchemy.ext.asyncio import AsyncSession

from app.keyboards import (
    back_kb, conditions_kb, yes_no_kb, auto_draw_type_kb, menu_kb
)
from app.texts import (
    REGISTER_CHAT_INSTRUCTIONS, ASK_TEMPLATE_TEXT, ASK_CONDITIONS_TEXT,
    ASK_WINNERS_TEXT, ASK_ANTI_FRAUD_TEXT, ASK_AUTO_DRAW_TEXT, ASK_AUTO_DRAW_TYPE_TEXT,
    ASK_AUTO_DRAW_THRESHOLD_TEXT, ASK_PREMIUM_ONLY_TEXT, PUBLISHED_TEXT
)
from app.models import Chat, Giveaway, AuditLog
from app.utils import extract_forwarded_chat_id, ensure_bot_admin, ensure_bot_admin_with_member_mgmt
from app.keyboards import participate_button

router = Router()

URL_ENTITY_TYPES = {"url", "text_link"}


class CreateFlow(StatesGroup):
    waiting_forward_target = State()
    waiting_template = State()
    waiting_cond_channels = State()
    waiting_winners_count = State()
    waiting_anti_fraud = State()
    waiting_auto_draw = State()
    waiting_auto_draw_threshold = State()
    waiting_premium_only = State()


async def audit(session: AsyncSession, actor: int, action: str, entity: str, entity_id: str | None, detail: str | None):
    session.add(AuditLog(actor_user_id=actor, action=action, entity=entity, entity_id=entity_id, detail=detail))


@router.callback_query(F.data.in_({"create:reg:channel", "create:reg:group"}))
async def create_register_target(cb: CallbackQuery, state: FSMContext):
    await state.set_state(CreateFlow.waiting_forward_target)
    await cb.message.edit_text(REGISTER_CHAT_INSTRUCTIONS, reply_markup=back_kb("menu:create"))
    await cb.answer()


@router.message(CreateFlow.waiting_forward_target)
async def on_forward_target(message: Message, bot: Bot, session: AsyncSession, state: FSMContext):
    chat_id = extract_forwarded_chat_id(message)
    if not chat_id:
        await message.answer("أعد توجيه رسالة من القناة/القروب المطلوب.")
        return

    ok, err = await ensure_bot_admin(bot, chat_id)
    if not ok:
        await message.answer(err)
        return

    tg_chat = await bot.get_chat(chat_id)

    c = await session.get(Chat, chat_id)
    if not c:
        c = Chat(id=chat_id, type=tg_chat.type, title=tg_chat.title, username=tg_chat.username)
        session.add(c)
        await session.commit()

    await state.update_data(target_chat_id=chat_id, target_chat_type=tg_chat.type, target_chat_title=tg_chat.title)
    await state.set_state(CreateFlow.waiting_template)
    await message.answer(ASK_TEMPLATE_TEXT, reply_markup=back_kb("menu:create"))


@router.message(CreateFlow.waiting_template)
async def on_template(message: Message, state: FSMContext):
    ents = message.entities or []
    for e in ents:
        if e.type in URL_ENTITY_TYPES:
            await message.answer("ممنوع الروابط نهائيًا. أعد إرسال الكليشة بدون روابط.")
            return

    text = message.html_text or message.text or ""
    if not text.strip():
        await message.answer("أرسل نص الكليشة.")
        return

    await state.update_data(template_text=text, cond_mode=None)
    await state.set_state(CreateFlow.waiting_cond_channels)
    await message.answer(ASK_CONDITIONS_TEXT, reply_markup=conditions_kb())


@router.callback_query(F.data == "create:back:template")
async def back_to_template(cb: CallbackQuery, state: FSMContext):
    await state.set_state(CreateFlow.waiting_template)
    await cb.message.edit_text(ASK_TEMPLATE_TEXT, reply_markup=back_kb("menu:create"))
    await cb.answer()


@router.callback_query(F.data == "cond:channel")
async def cond_channel(cb: CallbackQuery, state: FSMContext):
    await state.update_data(cond_mode="channel")
    await state.set_state(CreateFlow.waiting_cond_channels)
    await cb.message.edit_text("أرسل يوزر قناة الشرط مثل @X", reply_markup=back_kb("menu:create"))
    await cb.answer()


@router.callback_query(F.data == "cond:comment:paid")
async def cond_comment_paid(cb: CallbackQuery):
    await cb.answer("هذه الميزة مدفوعة عبر النجوم. اذهب إلى ❤️ التبرع لإتمام الشراء.", show_alert=True)


@router.callback_query(F.data == "cond:contest:todo")
async def cond_contest_todo(cb: CallbackQuery):
    await cb.answer("ميزة تصويت المتسابق مؤجلة في هذا الإصدار.", show_alert=True)


@router.callback_query(F.data == "cond:boost:todo")
async def cond_boost_todo(cb: CallbackQuery):
    await cb.answer("تعزيز قناة: لا يوجد تحقق رسمي مطبق هنا، لذلك لن ندّعي التحقق. مؤجل.", show_alert=True)


@router.callback_query(F.data == "cond:skip")
async def cond_skip(cb: CallbackQuery, state: FSMContext):
    await state.update_data(cond_channel_1=None, cond_channel_2=None)
    await state.set_state(CreateFlow.waiting_winners_count)
    await cb.message.edit_text(ASK_WINNERS_TEXT, reply_markup=back_kb("menu:create"))
    await cb.answer()


@router.message(CreateFlow.waiting_cond_channels)
async def on_cond_channels(message: Message, bot: Bot, session: AsyncSession, state: FSMContext):
    data = await state.get_data()
    if data.get("cond_mode") != "channel":
        await message.answer("اختر نوع الشرط من الأزرار.")
        return

    raw = (message.text or "").strip()
    if raw == "0":
        await state.update_data(cond_channel_1=None, cond_channel_2=None)
        await state.set_state(CreateFlow.waiting_winners_count)
        await message.answer(ASK_WINNERS_TEXT, reply_markup=back_kb("menu:create"))
        return

    lines = [x.strip() for x in raw.splitlines() if x.strip()]
    if not (1 <= len(lines) <= 2):
        await message.answer("يمكن إدخال قناتين كحد أقصى بسطرين.")
        return

    chat_ids: List[int] = []
    for username in lines:
        if not username.startswith("@"):
            await message.answer("أرسل يوزر قناة الشرط مثل @X")
            return
        try:
            chat = await bot.get_chat(username)
        except Exception:
            await message.answer("تعذر العثور على القناة. تأكد من اليوزر.")
            return

        ok, err = await ensure_bot_admin_with_member_mgmt(bot, chat.id)
        if not ok:
            await message.answer(err)
            return

        chat_ids.append(chat.id)

    c1 = chat_ids[0] if len(chat_ids) >= 1 else None
    c2 = chat_ids[1] if len(chat_ids) >= 2 else None
    await state.update_data(cond_channel_1=c1, cond_channel_2=c2)

    await state.set_state(CreateFlow.waiting_winners_count)
    await message.answer(ASK_WINNERS_TEXT, reply_markup=back_kb("menu:create"))


@router.message(CreateFlow.waiting_winners_count)
async def on_winners_count(message: Message, state: FSMContext):
    t = (message.text or "").strip()
    if not re.fullmatch(r"\d+", t):
        await message.answer("أدخل رقمًا صحيحًا.")
        return
    n = int(t)
    if n <= 0 or n > 100:
        await message.answer("اختر عددًا منطقيًا (1-100).")
        return
    await state.update_data(winners_count=n)

    await state.set_state(CreateFlow.waiting_anti_fraud)
    await message.answer(ASK_ANTI_FRAUD_TEXT, reply_markup=yes_no_kb("anti:yes", "anti:no"))


@router.callback_query(F.data.in_({"anti:yes", "anti:no"}))
async def anti_fraud(cb: CallbackQuery, state: FSMContext):
    await state.update_data(anti_fraud=(cb.data == "anti:yes"))
    await state.set_state(CreateFlow.waiting_auto_draw)
    await cb.message.edit_text(ASK_AUTO_DRAW_TEXT, reply_markup=yes_no_kb("autodraw:yes", "autodraw:no"))
    await cb.answer()


@router.callback_query(F.data == "autodraw:yes")
async def autodraw_yes(cb: CallbackQuery):
    await cb.message.edit_text(ASK_AUTO_DRAW_TYPE_TEXT, reply_markup=auto_draw_type_kb())
    await cb.answer()


@router.callback_query(F.data == "autodraw:no")
async def autodraw_no(cb: CallbackQuery, state: FSMContext):
    await state.update_data(auto_draw_enabled=False, auto_draw_entries_threshold=None)
    await state.set_state(CreateFlow.waiting_premium_only)
    await cb.message.edit_text(ASK_PREMIUM_ONLY_TEXT, reply_markup=yes_no_kb("prem:yes", "prem:no"))
    await cb.answer()


@router.callback_query(F.data == "autodraw:type:entries")
async def autodraw_entries(cb: CallbackQuery, state: FSMContext):
    await state.update_data(auto_draw_enabled=True)
    await state.set_state(CreateFlow.waiting_auto_draw_threshold)
    await cb.message.edit_text(ASK_AUTO_DRAW_THRESHOLD_TEXT, reply_markup=back_kb("menu:create"))
    await cb.answer()


@router.message(CreateFlow.waiting_auto_draw_threshold)
async def autodraw_threshold(message: Message, state: FSMContext):
    t = (message.text or "").strip()
    if not re.fullmatch(r"\d+", t):
        await message.answer("أدخل رقمًا صحيحًا.")
        return
    n = int(t)
    if n <= 0 or n > 1_000_000:
        await message.answer("اختر رقمًا منطقيًا.")
        return
    await state.update_data(auto_draw_entries_threshold=n)
    await state.set_state(CreateFlow.waiting_premium_only)
    await message.answer(ASK_PREMIUM_ONLY_TEXT, reply_markup=yes_no_kb("prem:yes", "prem:no"))


@router.callback_query(F.data.in_({"prem:yes", "prem:no"}))
async def premium_only(cb: CallbackQuery, bot: Bot, session: AsyncSession, state: FSMContext):
    data = await state.get_data()
    premium_only = (cb.data == "prem:yes")

    g = Giveaway(
        creator_user_id=cb.from_user.id,
        target_chat_id=data["target_chat_id"],
        target_chat_type=data["target_chat_type"],
        target_chat_title=data.get("target_chat_title"),
        template_text=data["template_text"],
        cond_channel_1=data.get("cond_channel_1"),
        cond_channel_2=data.get("cond_channel_2"),
        winners_count=int(data["winners_count"]),
        anti_fraud_recheck_on_draw=bool(data["anti_fraud"]),
        auto_draw_enabled=bool(data.get("auto_draw_enabled", False)),
        auto_draw_entries_threshold=data.get("auto_draw_entries_threshold"),
        premium_only=premium_only,
        paid_comment_condition_enabled=False,
    )
    session.add(g)
    await session.flush()
    await audit(session, cb.from_user.id, "create", "giveaway", str(g.id), f"target={g.target_chat_id}")
    await session.commit()
    await session.refresh(g)

    msg = await bot.send_message(
        chat_id=g.target_chat_id,
        text=g.template_text,
        reply_markup=participate_button(g.id),
        parse_mode="HTML"
    )
    g.published_message_id = msg.message_id
    await session.commit()

    await cb.message.edit_text(PUBLISHED_TEXT, reply_markup=menu_kb())
    await cb.answer()
    await state.clear()
