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
