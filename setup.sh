#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

PROJECT="telegram-roulette-bot"

# تأكيد أنك داخل مجلد المشروع
if [[ "$(basename "$(pwd)")" != "$PROJECT" ]]; then
  echo "خطأ: ادخل إلى مجلد المشروع أولًا:"
  echo "mkdir -p $PROJECT && cd $PROJECT"
  exit 1
fi

mkdir -p app/handlers

cat > requirements.txt <<'EOF'
aiogram==3.24.0
fastapi==0.115.6
uvicorn==0.30.6
gunicorn==23.0.0
SQLAlchemy==2.0.36
asyncpg==0.29.0
pydantic==2.10.3
pydantic-settings==2.7.0
APScheduler==3.10.4
python-dotenv==1.0.1
EOF

cat > render.yaml <<'EOF'
services:
  - type: web
    name: telegram-roulette-bot
    env: python
    plan: free
    buildCommand: pip install -r requirements.txt
    startCommand: gunicorn -k uvicorn.workers.UvicornWorker app.main:app --timeout 30
    autoDeploy: true
EOF

cat > README.md <<'EOF'
## Telegram Roulette Bot (Render + Webhook + Postgres)

### Required ENV on Render
- BOT_TOKEN
- BASE_URL (https://xxxx.onrender.com)
- WEBHOOK_SECRET
- DATABASE_URL
- HMAC_SECRET
- MANDATORY_CHANNELS (e.g. @Chan1,@Chan2)
- CHECK_MEMBERSHIP_EVERY_HOURS (e.g. 6)
- AUTO_DRAW_SCAN_SECONDS (e.g. 30)
- ADMIN_IDS (e.g. 123,456)
- SUPPORT_BOT (e.g. @MySupportBot)

### Start
- Open bot and send /start
EOF

cat > app/__init__.py <<'EOF'
# empty
EOF

cat > app/config.py <<'EOF'
from __future__ import annotations

from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import Field
from typing import List


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    bot_token: str = Field(alias="BOT_TOKEN")
    base_url: str = Field(alias="BASE_URL")
    webhook_secret: str = Field(alias="WEBHOOK_SECRET")

    database_url: str = Field(alias="DATABASE_URL")
    hmac_secret: str = Field(alias="HMAC_SECRET")

    mandatory_channels: str = Field(default="", alias="MANDATORY_CHANNELS")
    check_membership_every_hours: int = Field(default=6, alias="CHECK_MEMBERSHIP_EVERY_HOURS")
    auto_draw_scan_seconds: int = Field(default=30, alias="AUTO_DRAW_SCAN_SECONDS")

    admin_ids: str = Field(default="", alias="ADMIN_IDS")
    support_bot: str = Field(default="@SupportBot", alias="SUPPORT_BOT")

    @property
    def mandatory_channels_list(self) -> List[str]:
        return [x.strip() for x in self.mandatory_channels.split(",") if x.strip()]

    @property
    def admin_ids_list(self) -> List[int]:
        out: List[int] = []
        for part in [x.strip() for x in self.admin_ids.split(",") if x.strip()]:
            try:
                out.append(int(part))
            except ValueError:
                continue
        return out


settings = Settings()
EOF

cat > app/db.py <<'EOF'
from __future__ import annotations

from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from sqlalchemy.orm import DeclarativeBase
from app.config import settings


class Base(DeclarativeBase):
    pass


engine = create_async_engine(
    settings.database_url,
    echo=False,
    pool_pre_ping=True,
)

AsyncSessionLocal = async_sessionmaker(bind=engine, class_=AsyncSession, expire_on_commit=False)
EOF

cat > app/models.py <<'EOF'
from __future__ import annotations

from sqlalchemy import (
    BigInteger, Boolean, DateTime, ForeignKey, Integer, String, Text,
    UniqueConstraint, func
)
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.db import Base


class User(Base):
    __tablename__ = "users"
    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    username: Mapped[str | None] = mapped_column(String(64), nullable=True)
    language: Mapped[str | None] = mapped_column(String(16), nullable=True)

    gate_verified: Mapped[bool] = mapped_column(Boolean, default=False)
    notify_on_win: Mapped[bool] = mapped_column(Boolean, default=False)
    suspended: Mapped[bool] = mapped_column(Boolean, default=False)
    is_banned: Mapped[bool] = mapped_column(Boolean, default=False)

    created_at: Mapped[str] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Chat(Base):
    __tablename__ = "chats"
    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    type: Mapped[str] = mapped_column(String(16))
    title: Mapped[str | None] = mapped_column(String(255), nullable=True)
    username: Mapped[str | None] = mapped_column(String(128), nullable=True)

    is_banned: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[str] = mapped_column(DateTime(timezone=True), server_default=func.now())


class ChannelLog(Base):
    __tablename__ = "channel_logs"
    source_chat_id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    owner_user_id: Mapped[int] = mapped_column(BigInteger)
    log_chat_id: Mapped[int] = mapped_column(BigInteger)
    created_at: Mapped[str] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Giveaway(Base):
    __tablename__ = "giveaways"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    creator_user_id: Mapped[int] = mapped_column(BigInteger, index=True)

    target_chat_id: Mapped[int] = mapped_column(BigInteger, index=True)
    target_chat_type: Mapped[str] = mapped_column(String(16))
    target_chat_title: Mapped[str | None] = mapped_column(String(255), nullable=True)

    template_text: Mapped[str] = mapped_column(Text)

    cond_channel_1: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
    cond_channel_2: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
    premium_only: Mapped[bool] = mapped_column(Boolean, default=False)

    anti_fraud_recheck_on_draw: Mapped[bool] = mapped_column(Boolean, default=True)
    winners_count: Mapped[int] = mapped_column(Integer, default=1)

    auto_draw_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    auto_draw_entries_threshold: Mapped[int | None] = mapped_column(Integer, nullable=True)

    published_message_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    is_drawn: Mapped[bool] = mapped_column(Boolean, default=False)

    paid_comment_condition_enabled: Mapped[bool] = mapped_column(Boolean, default=False)

    created_at: Mapped[str] = mapped_column(DateTime(timezone=True), server_default=func.now())
    drawn_at: Mapped[str | None] = mapped_column(DateTime(timezone=True), nullable=True)


class Entry(Base):
    __tablename__ = "entries"
    __table_args__ = (UniqueConstraint("giveaway_id", "user_id", name="uq_entry_giveaway_user"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    giveaway_id: Mapped[int] = mapped_column(ForeignKey("giveaways.id"), index=True)
    user_id: Mapped[int] = mapped_column(BigInteger, index=True)
    username: Mapped[str | None] = mapped_column(String(64), nullable=True)

    seq_no: Mapped[int] = mapped_column(Integer)
    excluded: Mapped[bool] = mapped_column(Boolean, default=False)

    created_at: Mapped[str] = mapped_column(DateTime(timezone=True), server_default=func.now())
    giveaway = relationship("Giveaway")


class Winner(Base):
    __tablename__ = "winners"
    __table_args__ = (UniqueConstraint("giveaway_id", "user_id", name="uq_winner_giveaway_user"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    giveaway_id: Mapped[int] = mapped_column(ForeignKey("giveaways.id"), index=True)
    user_id: Mapped[int] = mapped_column(BigInteger, index=True)
    username: Mapped[str | None] = mapped_column(String(64), nullable=True)
    created_at: Mapped[str] = mapped_column(DateTime(timezone=True), server_default=func.now())


class StarsPurchase(Base):
    __tablename__ = "stars_purchases"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(BigInteger, index=True)

    product_key: Mapped[str] = mapped_column(String(64))
    amount_stars: Mapped[int] = mapped_column(Integer)

    giveaway_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    payload: Mapped[str] = mapped_column(String(128), unique=True)

    is_paid: Mapped[bool] = mapped_column(Boolean, default=False)
    telegram_charge_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    created_at: Mapped[str] = mapped_column(DateTime(timezone=True), server_default=func.now())
    paid_at: Mapped[str | None] = mapped_column(DateTime(timezone=True), nullable=True)


class AuditLog(Base):
    __tablename__ = "audit_logs"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    actor_user_id: Mapped[int | None] = mapped_column(BigInteger, nullable=True, index=True)
    action: Mapped[str] = mapped_column(String(64), index=True)
    entity: Mapped[str] = mapped_column(String(64))
    entity_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    detail: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[str] = mapped_column(DateTime(timezone=True), server_default=func.now())
EOF

cat > app/security.py <<'EOF'
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import time
from typing import Any, Dict, Optional
from app.config import settings


def _b64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("utf-8").rstrip("=")


def _b64url_decode(data: str) -> bytes:
    pad = "=" * (-len(data) % 4)
    return base64.urlsafe_b64decode(data + pad)


def sign_payload(payload: Dict[str, Any]) -> str:
    body = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    b64 = _b64url_encode(body)
    sig = hmac.new(settings.hmac_secret.encode("utf-8"), b64.encode("utf-8"), hashlib.sha256).digest()
    return f"{b64}.{_b64url_encode(sig)}"


def verify_payload(token: str, max_age_seconds: int = 7 * 24 * 3600) -> Optional[Dict[str, Any]]:
    try:
        b64, sig = token.split(".", 1)
        expected = hmac.new(settings.hmac_secret.encode("utf-8"), b64.encode("utf-8"), hashlib.sha256).digest()
        if not hmac.compare_digest(_b64url_encode(expected), sig):
            return None
        data = json.loads(_b64url_decode(b64).decode("utf-8"))
        ts = int(data.get("ts", 0))
        now = int(time.time())
        if ts <= 0 or abs(now - ts) > max_age_seconds:
            return None
        return data
    except Exception:
        return None


def new_nonce(n: int = 10) -> str:
    return _b64url_encode(os.urandom(n))
EOF

cat > app/texts.py <<'EOF'
GATE_TEXT = (
    "قبل استخدام البوت يجب الاشتراك في القنوات الإلزامية.\n\n"
    "القائمة:\n"
    "1) القناة\n"
    "2) لقد اشتركت\n"
    "3) ذكرني إذا فزت"
)

MENU_TEXT = "اختر من القائمة الرئيسية:"

CREATE_PICK_CHAT_TEXT = "يجري تحديد القناة أو القروب للسحب…"
REGISTER_CHAT_INSTRUCTIONS = (
    "أضف البوت مشرفًا\n"
    "أعد توجيه رسالة من القناة/القروب\n"
    "ملاحظة: كل المشرفين يمكنهم استخدام البوت بعد إضافته."
)

ASK_TEMPLATE_TEXT = "✍️ أرسل كليشة المسابقة الآن…"
ASK_CONDITIONS_TEXT = "إضافة شروط للسحب"
ASK_WINNERS_TEXT = "يرجى إدخال عدد الفائزين"
ASK_ANTI_FRAUD_TEXT = "هل تريد منع الغش في سحوباتك؟"
ASK_AUTO_DRAW_TEXT = "هل تريد ضبط السحب التلقائي للروليت؟"
ASK_AUTO_DRAW_TYPE_TEXT = "اختر نوع السحب التلقائي"
ASK_AUTO_DRAW_THRESHOLD_TEXT = "يرجى إدخال عدد المشاركين الذي عنده تريد تفعيل السحب التلقائي"
ASK_PREMIUM_ONLY_TEXT = "ميزة جديدة: جعل السحب متاحًا فقط لمستخدمي Telegram Premium"

PUBLISHED_TEXT = "تم نشر السحب"
POPUP_ENABLED_NOTIFY = "تم تفعيل الإشعار"
NOTIFY_INFO = "ستتلقى إشعارًا إذا فزت… بشرط ألا تحذف المحادثة"

LOG_ENTRY_NEW = "مشاركة جديدة في سحبك!"

CHANNEL_LOG_ENTRY_TEXT = (
    "سجل القناة:\n"
    "يجب أن تكون مالك القناة لربطها كسجل.\n"
)
EOF

cat > app/keyboards.py <<'EOF'
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
EOF

cat > app/utils.py <<'EOF'
from __future__ import annotations

from aiogram import Bot
from aiogram.types import Message
from aiogram.exceptions import TelegramBadRequest
from typing import Optional, Tuple


def extract_forwarded_chat_id(msg: Message) -> Optional[int]:
    try:
        if msg.forward_origin and getattr(msg.forward_origin, "type", None) == "chat":
            chat = getattr(msg.forward_origin, "chat", None)
            if chat:
                return chat.id
    except Exception:
        pass

    if msg.forward_from_chat:
        return msg.forward_from_chat.id

    return None


async def ensure_bot_admin(bot: Bot, chat_id: int) -> Tuple[bool, str]:
    try:
        me = await bot.get_me()
        cm = await bot.get_chat_member(chat_id, me.id)
        if cm.status not in ("administrator", "creator"):
            return False, "يجب إضافة البوت مشرفًا في هذه الجهة."
        return True, ""
    except TelegramBadRequest:
        return False, "تعذر التحقق. تأكد من أن البوت مضاف."
    except Exception:
        return False, "خطأ غير متوقع أثناء التحقق."


async def ensure_bot_admin_with_member_mgmt(bot: Bot, chat_id: int) -> Tuple[bool, str]:
    try:
        me = await bot.get_me()
        cm = await bot.get_chat_member(chat_id, me.id)
        if cm.status == "creator":
            return True, ""
        if cm.status != "administrator":
            return False, "يجب إضافة البوت مشرفًا في قناة الشرط."
        can_restrict = getattr(cm, "can_restrict_members", False)
        if not can_restrict:
            return False, "يجب منح البوت صلاحية إدارة الأعضاء في قناة الشرط."
        return True, ""
    except Exception:
        return False, "تعذر التحقق من صلاحيات البوت في قناة الشرط."
EOF

cat > app/scheduler.py <<'EOF'
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
EOF

cat > app/handlers/__init__.py <<'EOF'
from . import start_gate, menu, giveaway_create, participate, channel_log, stats, donate_stars, terms_privacy, admin, entry_actions
EOF

cat > app/handlers/start_gate.py <<'EOF'
from __future__ import annotations

from aiogram import Router, Bot, F
from aiogram.types import Message, CallbackQuery
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import User
from app.keyboards import gate_kb, menu_kb
from app.texts import GATE_TEXT, MENU_TEXT, POPUP_ENABLED_NOTIFY, NOTIFY_INFO
from app.config import settings

router = Router()


async def upsert_user(session: AsyncSession, tg_user) -> User:
    u = await session.get(User, tg_user.id)
    if not u:
        u = User(
            id=tg_user.id,
            username=tg_user.username,
            language=tg_user.language_code,
        )
        session.add(u)
        await session.commit()
        await session.refresh(u)
    else:
        changed = False
        if u.username != tg_user.username:
            u.username = tg_user.username
            changed = True
        if u.language != tg_user.language_code:
            u.language = tg_user.language_code
            changed = True
        if changed:
            await session.commit()
    return u


async def user_in_all_mandatory(bot: Bot, user_id: int) -> bool:
    if not settings.mandatory_channels_list:
        return True

    for ch in settings.mandatory_channels_list:
        try:
            if ch.startswith("@"):
                chat = await bot.get_chat(ch)
            elif "t.me/" in ch:
                username = ch.split("t.me/")[-1].split("?")[0].strip("/")
                chat = await bot.get_chat(f"@{username}")
            else:
                return False
            cm = await bot.get_chat_member(chat.id, user_id)
            if cm.status in ("left", "kicked"):
                return False
        except Exception:
            return False
    return True


@router.message(F.text == "/start")
async def start_cmd(message: Message, bot: Bot, session: AsyncSession):
    u = await upsert_user(session, message.from_user)
    if u.is_banned:
        return

    if u.gate_verified and not u.suspended:
        await message.answer(MENU_TEXT, reply_markup=menu_kb())
        return

    await message.answer(GATE_TEXT, reply_markup=gate_kb())


@router.callback_query(F.data == "gate:check")
async def gate_check(cb: CallbackQuery, bot: Bot, session: AsyncSession):
    u = await upsert_user(session, cb.from_user)
    if u.is_banned:
        await cb.answer("موقوف.", show_alert=True)
        return

    ok = await user_in_all_mandatory(bot, u.id)
    if not ok:
        await cb.answer("لم يتم العثور على اشتراكك في القنوات الإلزامية.", show_alert=True)
        return

    u.gate_verified = True
    u.suspended = False
    await session.commit()

    await cb.message.edit_text(MENU_TEXT, reply_markup=menu_kb())
    await cb.answer("تم التحقق بنجاح.", show_alert=False)


@router.callback_query(F.data == "notify:toggle")
async def toggle_notify(cb: CallbackQuery, session: AsyncSession):
    u = await upsert_user(session, cb.from_user)
    if u.is_banned:
        await cb.answer("موقوف.", show_alert=True)
        return
    u.notify_on_win = True
    await session.commit()
    await cb.answer(POPUP_ENABLED_NOTIFY, show_alert=True)
    try:
        await cb.message.answer(NOTIFY_INFO)
    except Exception:
        pass


@router.callback_query(F.data == "noop")
async def noop(cb: CallbackQuery):
    await cb.answer("…", show_alert=False)
EOF

cat > app/handlers/menu.py <<'EOF'
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
EOF

cat > app/handlers/giveaway_create.py <<'EOF'
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
EOF

cat > app/handlers/participate.py <<'EOF'
from __future__ import annotations

import time
from aiogram import Router, Bot, F
from aiogram.types import CallbackQuery
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func

from app.security import verify_payload
from app.models import Giveaway, Entry, User, ChannelLog, AuditLog
from app.keyboards import entry_admin_kb
from app.texts import LOG_ENTRY_NEW

router = Router()

_last_click = {}  # (user_id, giveaway_id) -> ts


async def audit(session: AsyncSession, actor: int | None, action: str, entity: str, entity_id: str | None, detail: str | None):
    session.add(AuditLog(actor_user_id=actor, action=action, entity=entity, entity_id=entity_id, detail=detail))


async def check_user_gate(session: AsyncSession, user_id: int) -> bool:
    u = await session.get(User, user_id)
    if not u or u.is_banned:
        return False
    if not u.gate_verified or u.suspended:
        return False
    return True


async def conditions_ok(bot: Bot, g: Giveaway, cb: CallbackQuery) -> tuple[bool, str]:
    if g.premium_only and not (cb.from_user.is_premium is True):
        return False, "هذا السحب متاح فقط لمستخدمي Telegram Premium."

    for cond in (g.cond_channel_1, g.cond_channel_2):
        if cond:
            try:
                cm = await bot.get_chat_member(cond, cb.from_user.id)
                if cm.status in ("left", "kicked"):
                    return False, "يجب استيفاء شروط الاشتراك في قناة الشرط."
            except Exception:
                return False, "تعذر التحقق من شروط القناة الآن."

    if g.paid_comment_condition_enabled:
        return False, "شرط التعليق مفعل لكن لا يوجد تحقق رسمي مطبق في هذا الإصدار."

    return True, ""


@router.callback_query(F.data.startswith("p:"))
async def participate(cb: CallbackQuery, bot: Bot, session: AsyncSession):
    token = cb.data.split("p:", 1)[1]
    data = verify_payload(token)
    if not data:
        await cb.answer("رابط مشاركة غير صالح.", show_alert=True)
        return

    giveaway_id = int(data["g"])
    now = time.time()
    key = (cb.from_user.id, giveaway_id)
    if now - _last_click.get(key, 0) < 2.0:
        await cb.answer("تمهل قليلًا.", show_alert=False)
        return
    _last_click[key] = now

    if not await check_user_gate(session, cb.from_user.id):
        await cb.answer("يجب إتمام بوابة الاشتراك أولًا.", show_alert=True)
        return

    g = await session.get(Giveaway, giveaway_id)
    if not g:
        await cb.answer("السحب غير موجود.", show_alert=True)
        return
    if g.is_drawn:
        await cb.answer("انتهى السحب.", show_alert=True)
        return

    ok, err = await conditions_ok(bot, g, cb)
    if not ok:
        await cb.answer(err, show_alert=True)
        return

    seq_no = (await session.execute(
        select(func.count(Entry.id)).where(Entry.giveaway_id == g.id)
    )).scalar_one() + 1

    e = Entry(
        giveaway_id=g.id,
        user_id=cb.from_user.id,
        username=cb.from_user.username,
        seq_no=seq_no,
        excluded=False,
    )
    session.add(e)
    try:
        await session.commit()
    except Exception:
        await session.rollback()
        await cb.answer("أنت مشارك بالفعل.", show_alert=True)
        return

    await audit(session, cb.from_user.id, "entry_create", "giveaway", str(g.id), f"seq={seq_no}")
    await session.commit()

    await cb.answer("تمت المشاركة.", show_alert=False)

    chlog = await session.get(ChannelLog, g.target_chat_id)
    if chlog:
        text = (
            f"{LOG_ENTRY_NEW}\n"
            f"{('@' + cb.from_user.username) if cb.from_user.username else 'بدون يوزر'}\n"
            f"{cb.from_user.id}\n"
            f"{int(time.time())}\n"
            f"عدد المشاركين: {seq_no}"
        )
        try:
            await bot.send_message(
                chat_id=chlog.log_chat_id,
                text=text,
                reply_markup=entry_admin_kb(cb.from_user.id, e.id),
            )
        except Exception:
            pass
EOF

cat > app/handlers/entry_actions.py <<'EOF'
from __future__ import annotations

from aiogram import Router, F
from aiogram.types import CallbackQuery
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Entry, AuditLog

router = Router()


async def audit(session: AsyncSession, actor: int | None, action: str, entity: str, entity_id: str | None, detail: str | None):
    session.add(AuditLog(actor_user_id=actor, action=action, entity=entity, entity_id=entity_id, detail=detail))


@router.callback_query(F.data.startswith("entry:exclude:"))
async def exclude_entry(cb: CallbackQuery, session: AsyncSession):
    try:
        entry_id = int(cb.data.split("entry:exclude:", 1)[1])
    except Exception:
        await cb.answer("خطأ.", show_alert=True)
        return

    e = await session.get(Entry, entry_id)
    if not e:
        await cb.answer("غير موجود.", show_alert=True)
        return

    if not e.excluded:
        e.excluded = True
        await audit(session, cb.from_user.id, "exclude", "entry", str(entry_id), None)
        await session.commit()

    await cb.answer("تم استبعاده", show_alert=True)
EOF

cat > app/handlers/channel_log.py <<'EOF'
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
EOF

cat > app/handlers/stats.py <<'EOF'
from __future__ import annotations

from aiogram import Router, F
from aiogram.types import CallbackQuery
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, desc

from app.models import Entry, Giveaway
from app.keyboards import menu_kb

router = Router()


@router.callback_query(F.data == "menu:stats")
async def stats(cb: CallbackQuery, session: AsyncSession):
    q1 = await session.execute(
        select(func.count(Entry.id))
        .join(Giveaway, Giveaway.id == Entry.giveaway_id)
        .where(Entry.user_id == cb.from_user.id, Giveaway.is_drawn == False)
    )
    current = q1.scalar_one()

    q2 = await session.execute(
        select(Giveaway.target_chat_id, func.count(Entry.id).label("cnt"))
        .join(Entry, Entry.giveaway_id == Giveaway.id)
        .group_by(Giveaway.target_chat_id)
        .order_by(desc("cnt"))
        .limit(10)
    )
    top = q2.all()

    text = f"عدد السحوبات التي أنا مشترك فيها حاليًا: {current}\n\nأفضل 10 قنوات (حسب عدد المشاركات داخل البوت):\n"
    for chat_id, cnt in top:
        text += f"- {chat_id}: اشتراك {cnt}\n"

    await cb.message.edit_text(text, reply_markup=menu_kb())
    await cb.answer()
EOF

cat > app/handlers/terms_privacy.py <<'EOF'
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
EOF

cat > app/handlers/donate_stars.py <<'EOF'
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
EOF

cat > app/handlers/admin.py <<'EOF'
from __future__ import annotations

from aiogram import Router, F
from aiogram.types import Message
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models import User, Chat, AuditLog

router = Router()


def is_admin(user_id: int) -> bool:
    return user_id in settings.admin_ids_list


async def audit(session: AsyncSession, actor: int | None, action: str, entity: str, entity_id: str | None, detail: str | None):
    session.add(AuditLog(actor_user_id=actor, action=action, entity=entity, entity_id=entity_id, detail=detail))


@router.message(F.text.startswith("/ban_user"))
async def ban_user(message: Message, session: AsyncSession):
    if not is_admin(message.from_user.id):
        return
    parts = (message.text or "").split()
    if len(parts) != 2:
        await message.answer("استخدم: /ban_user <user_id>")
        return
    uid = int(parts[1])
    u = await session.get(User, uid)
    if not u:
        await message.answer("غير موجود.")
        return
    u.is_banned = True
    await audit(session, message.from_user.id, "ban_user", "user", str(uid), None)
    await session.commit()
    await message.answer("تم حظر المستخدم.")


@router.message(F.text.startswith("/ban_chat"))
async def ban_chat(message: Message, session: AsyncSession):
    if not is_admin(message.from_user.id):
        return
    parts = (message.text or "").split()
    if len(parts) != 2:
        await message.answer("استخدم: /ban_chat <chat_id>")
        return
    cid = int(parts[1])
    c = await session.get(Chat, cid)
    if not c:
        c = Chat(id=cid, type="unknown", title=None, username=None, is_banned=True)
        session.add(c)
    else:
        c.is_banned = True
    await audit(session, message.from_user.id, "ban_chat", "chat", str(cid), None)
    await session.commit()
    await message.answer("تم حظر القناة/القروب.")
EOF

cat > app/main.py <<'EOF'
from __future__ import annotations

import logging
from fastapi import FastAPI, Request, HTTPException

from aiogram import Bot, Dispatcher
from aiogram.types import Update
from aiogram.fsm.storage.memory import MemoryStorage

from app.config import settings
from app.db import engine, Base, AsyncSessionLocal
from app.scheduler import scheduler, check_mandatory_membership_job, auto_draw_job

from app.handlers import (
    start_gate, menu, giveaway_create, participate, channel_log, stats, donate_stars, terms_privacy, admin, entry_actions
)

logging.basicConfig(level=logging.INFO)

bot = Bot(token=settings.bot_token, parse_mode="HTML")
dp = Dispatcher(storage=MemoryStorage())

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

0
@app.on_event("startup")
async def on_startup():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    webhook_url = f"{settings.base_url}/webhook/{settings.webhook_secret}"
    await bot.set_webhook(webhook_url, drop_pending_updates=True)

    scheduler.add_job(check_mandatory_membership_job, "interval", hours=settings.check_membership_every_hours, args=[bot])
    scheduler.add_job(auto_draw_job, "interval", seconds=settings.auto_draw_scan_seconds, args=[bot])
    scheduler.start()
    logging.info("Startup complete.")


@app.on_event("shutdown")
async def on_shutdown():
    scheduler.shutdown(wait=False)
    await bot.delete_webhook(drop_pending_updates=True)
    await bot.session.close()


@app.post("/webhook/{secret}")
async def webhook(secret: str, request: Request):
    if secret != settings.webhook_secret:
        raise HTTPException(status_code=403, detail="Forbidden")

    data = await request.json()
    update = Update.model_validate(data)

    async with AsyncSessionLocal() as session:
        dp["session"] = session
        await dp.feed_update(bot, update)

    return {"ok": True}
EOF

echo
echo "تم إنشاء المشروع بالكامل داخل: $(pwd)"
echo "الخطوة التالية: ارفع المشروع إلى GitHub (سأعطيك أوامر git جاهزة عندما تقول: جاهز للرفع)"


