from __future__ import annotations

from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from sqlalchemy.orm import DeclarativeBase
from app.config import settings


class Base(DeclarativeBase):
    pass


def _normalize_db_url(url: str) -> str:
    """
    Render أحيانًا يعطي postgres://
    SQLAlchemy يفضّل postgresql://
    ونحوّل الديالك إلى psycopg للـ async.
    """
    url = url.strip()

    # postgres:// -> postgresql://
    if url.startswith("postgres://"):
        url = "postgresql://" + url[len("postgres://"):]

    # إن كان المستخدم وضع dialect قديم أو تركه بدون
    # نجبره إلى postgresql+psycopg://
    if url.startswith("postgresql://"):
        url = "postgresql+psycopg://" + url[len("postgresql://"):]
    elif url.startswith("postgresql+asyncpg://"):
        url = "postgresql+psycopg://" + url[len("postgresql+asyncpg://"):]
    elif url.startswith("postgresql+psycopg://"):
        pass
    else:
        # لو جاء بصيغة غير متوقعة، نتركه كما هو (لكن هذا نادر)
        pass

    return url


engine = create_async_engine(
    _normalize_db_url(settings.database_url),
    echo=False,
    pool_pre_ping=True,
)

AsyncSessionLocal = async_sessionmaker(bind=engine, class_=AsyncSession, expire_on_commit=False)
