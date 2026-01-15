from aiogram import Bot, Dispatcher
from app.config import settings

bot = Bot(token=settings.BOT_TOKEN)
dp = Dispatcher()
