from __future__ import annotations

import random
from datetime import datetime, timezone

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from sqlalchemy import select, func
from aiogram import Bot

from app.config import settings
from app.models import User, Giveaway, Entry, Winner, AuditLog
from app.db import AsyncSessionLocal

scheduler = AsyncIOScheduler(timezone="UTC")


async def audit(session, actor: int | None, action: str, entity: str, entity_id: str | None, detail: str | None):
    session.add(AuditLog(actor_user_id=actor, action=action, entity=entity, entity_id=entity_id, detail=detail))


async def check_mandatory_membership_job(bot: Bot):
    if not settings.mandatory_channels_list:
        return

    async with AsyncSessionLocal() as session:
        users = (await session.execute(
            select(User).where(User.gate_verified == True, User.is_banned == False)
        )).scalars().all()
        if not users:
            return

        mandatory_chat_ids = []
        for ch in settings.mandatory_channels_list:
            try:
                if ch.startswith("@"):
                    chat = await bot.get_chat(ch)
                elif "t.me/" in ch:
                    username = ch.split("t.me/")[-1].split("?")[0].strip("/")
                    chat = await bot.get_chat(f"@{username}")
                else:
                    continue
                mandatory_chat_ids.append(chat.id)
            except Exception:
                continue

        for u in users:
            ok = True
            for cid in mandatory_chat_ids:
                try:
                    cm = await bot.get_chat_member(cid, u.id)
                    if cm.status in ("left", "kicked"):
                        ok = False
                        break
                except Exception:
                    # لا نعلّق تلقائيًا إذا تعذر التحقق
                    continue
            if not ok and not u.suspended:
                u.suspended = True
            if ok and u.suspended:
                u.suspended = False

        await session.commit()


async def _eligible_on_draw(bot: Bot, g: Giveaway, user_id: int) -> bool:
    # شروط القنوات فقط (Premium لا يمكن إعادة التحقق منه رسميًا من API)
    for cond in (g.cond_channel_1, g.cond_channel_2):
        if cond:
            try:
                cm = await bot.get_chat_member(cond, user_id)
                if cm.status in ("left", "kicked"):
                    return False
            except Exception:
                if g.anti_fraud_recheck_on_draw:
                    return False
    if g.paid_comment_condition_enabled:
        # لا ندّعي تحقق رسمي
        return False
    return True


async def auto_draw_job(bot: Bot):
    async with AsyncSessionLocal() as session:
        giveaways = (await session.execute(
            select(Giveaway).where(
                Giveaway.auto_draw_enabled == True,
                Giveaway.is_drawn == False,
                Giveaway.auto_draw_entries_threshold.is_not(None),
            )
        )).scalars().all()

        for g in giveaways:
            total_entries = (await session.execute(
                select(func.count(Entry.id)).where(Entry.giveaway_id == g.id, Entry.excluded == False)
            )).scalar_one()

            if total_entries < int(g.auto_draw_entries_threshold or 0):
                continue

            entries = (await session.execute(
                select(Entry).where(Entry.giveaway_id == g.id, Entry.excluded == False).order_by(Entry.id.asc())
            )).scalars().all()

            candidates = []
            if g.anti_fraud_recheck_on_draw:
                for e in entries:
                    if await _eligible_on_draw(bot, g, e.user_id):
                        candidates.append(e)
            else:
                candidates = entries

            if not candidates:
                g.is_drawn = True
                g.drawn_at = datetime.now(timezone.utc)
                await audit(session, g.creator_user_id, "draw", "giveaway", str(g.id), "No eligible candidates")
                await session.commit()
                continue

            k = min(g.winners_count, len(candidates))
            winners = random.sample(candidates, k=k)

            for w in winners:
                session.add(Winner(giveaway_id=g.id, user_id=w.user_id, username=w.username))

            g.is_drawn = True
            g.drawn_at = datetime.now(timezone.utc)
            await audit(session, g.creator_user_id, "draw", "giveaway", str(g.id), f"winners={k}")
            await session.commit()
