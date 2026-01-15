from fastapi import FastAPI, Request, HTTPException
from aiogram.types import Update

from app.bot import bot, dp
from app.config import settings
from app.db import connect_db, close_db

app = FastAPI()


@app.on_event("startup")
async def on_startup():
    await connect_db()

    webhook_url = f"{settings.BASE_URL}/webhook/{settings.WEBHOOK_SECRET}"
    await bot.set_webhook(webhook_url, drop_pending_updates=True)


@app.on_event("shutdown")
async def on_shutdown():
    await bot.delete_webhook()
    await close_db()
    await bot.session.close()


@app.post("/webhook/{secret}")
async def webhook(secret: str, request: Request):
    if secret != settings.WEBHOOK_SECRET:
        raise HTTPException(status_code=403)

    data = await request.json()
    update = Update.model_validate(data)
    await dp.feed_update(bot, update)
    return {"ok": True}
