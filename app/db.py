import asyncpg
from app.config import settings


class Database:
    pool: asyncpg.Pool | None = None


db = Database()


async def connect_db():
    db.pool = await asyncpg.create_pool(
        dsn=settings.DATABASE_URL,
        min_size=1,
        max_size=5,
    )


async def close_db():
    if db.pool:
        await db.pool.close()
