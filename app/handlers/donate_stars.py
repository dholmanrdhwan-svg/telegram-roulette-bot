from __future__ import annotations

import uuid
from datetime import datetime, timezone

from aiogram import Router, Bot, F
from aiogram.types import CallbackQuery, LabeledPrice, Message, PreCheckoutQuery
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.keyboards import menu_kb, yes_no_kb
from app.models import StarsPurchase, AuditLog

router = Router()

PRODUCT_KEY = "comment_condition"
PRICE_STARS = 20


async def audit(session: AsyncSession, actor: int | None, action: str, entity: str, entity_id: str | None, detail: str | None):
    session.add(AuditLog(actor_user_id=actor, action=action, entity=entity, entity_id=entity_id, detail=detail))


@router.callback_query(F.data == "menu:donate")
async def donate_menu(cb: CallbackQuery):
    txt = (
        "❤️ التبرع / النجوم\n\n"
        f"شراء ميزة: تعليق على منشور (فتح زر الشرط المدفوع)\n"
        f"السعر: {PRICE_STARS} نجمة\n\n"
        "ملاحظة: لا يوجد استرجاع."
    )
    kb = yes_no_kb("stars:buy:comment", "menu:home")
    await cb.message.edit_text(txt, reply_markup=kb)
    await cb.answer()


@router.callback_query(F.data == "stars:buy:comment")
async def stars_buy(cb: CallbackQuery, bot: Bot, session: AsyncSession):
    payload = f"stars:{PRODUCT_KEY}:{uuid.uuid4().hex}"

    p = StarsPurchase(
        user_id=cb.from_user.id,
        product_key=PRODUCT_KEY,
        amount_stars=PRICE_STARS,
        payload=payload,
        is_paid=False,
    )
    session.add(p)
    await session.commit()

    prices = [LabeledPrice(label="شراء ميزة", amount=PRICE_STARS)]
    await bot.send_invoice(
        chat_id=cb.from_user.id,
        title="شراء ميزة",
        description="شراء ميزة تعليق على منشور (مدفوع)",
        payload=payload,
        currency="XTR",
        prices=prices,
        provider_token="",  # Stars
    )
    await cb.answer()


@router.pre_checkout_query()
async def pre_checkout(pre: PreCheckoutQuery, bot: Bot):
    if pre.invoice_payload.startswith("stars:"):
        await bot.answer_pre_checkout_query(pre.id, ok=True)
    else:
        await bot.answer_pre_checkout_query(pre.id, ok=False, error_message="Payload غير صالح.")


@router.message(F.successful_payment)
async def on_successful_payment(message: Message, session: AsyncSession):
    sp = message.successful_payment
    payload = sp.invoice_payload

    q = await session.execute(select(StarsPurchase).where(StarsPurchase.payload == payload))
    purchase = q.scalars().first()
    if not purchase:
        return

    purchase.is_paid = True
    purchase.telegram_charge_id = sp.telegram_payment_charge_id
    purchase.paid_at = datetime.now(timezone.utc)

    await audit(session, message.from_user.id, "stars_paid", "stars_purchase", str(purchase.id), f"product={purchase.product_key}")
    await session.commit()

    await message.answer("تم تأكيد الشراء بنجاح.", reply_markup=menu_kb())
