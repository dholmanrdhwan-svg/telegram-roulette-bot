from __future__ import annotations

import logging
from fastapi import FastAPI, Request, HTTPException

from aiogram import Bot, Dispatcher
from aiogram.client.default import DefaultBotProperties
from aiogram.types import Update
from aiogram.fsm.storage.memory import MemoryStorage

from app.config import settings
from app.db import engine, Base, AsyncSessionLocal
from app.scheduler import scheduler, check_mandatory_membership_job, auto_draw_job

from app.handlers import (
    start_gate,
    menu,
    giveaway_create,
    participate,
    channel_log,
    stats,
    donate_stars,
    terms_privacy,
    admin,
    entry_actions,
)

logging.basicConfig(level=logging.INFO)

# ✅ aiogram v3: default bot properties بدل parse_mode داخل Bot()
bot = Bot(
    token=settings.bot_token,
    default=DefaultBotProperties(parse_mode="HTML"),
)

dp = Dispatcher(storage=MemoryStorage())

# Routers
dp.include_router(start_gate.router)
dp.include_router(menu.router)
dp.include_router(giveaway_create.router)
dp.include_router(participate.router)
dp.include_router(channel_log.router)
dp.include_router(stats.router)
dp.include_router(donate_stars.router)
dp.include_router(terms_privacy.router)
dp.include_router(admin.router)
dp.include_router(entry_actions.router)

app = FastAPI()


@app.on_event("startup")
async def on_startup():
    # إنشاء الجداول
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    # ضبط webhook
    webhook_url = f"{settings.base_url}/webhook/{settings.webhook_secret}"
    await bot.set_webhook(webhook_url, drop_pending_updates=True)

    # جدولة التحقق الدوري + السحب التلقائي
    scheduler.add_job(
        check_mandatory_membership_job,
        "interval",
        hours=settings.check_membership_every_hours,
        args=[bot],
    )
    scheduler.add_job(
        auto_draw_job,
        "interval",
        seconds=settings.auto_draw_scan_seconds,
        args=[bot],
    )
    scheduler.start()

    logging.info("Startup complete.")


@app.on_event("shutdown")
async def on_shutdown():
    scheduler.shutdown(wait=False)
    await bot.delete_webhook(drop_pending_updates=True)
    await bot.session.close()


@app.post("/webhook/{secret}")
async def webhook(secret: str, request: Request):
    # حماية مسار الويبهوك
    if secret != settings.webhook_secret:
        raise HTTPException(status_code=403, detail="Forbidden")

    data = await request.json()
    update = Update.model_validate(data)

    # تمرير session لآليات dependency داخل aiogram
    async with AsyncSessionLocal() as session:
        dp["session"] = session
        await dp.feed_update(bot, update)

    return {"ok": True}
