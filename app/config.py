from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    BOT_TOKEN: str
    BASE_URL: str
    WEBHOOK_SECRET: str
    DATABASE_URL: str

    ADMIN_IDS: str
    SUPPORT_BOT: str = "@Rdhulman"

    class Config:
        env_file = ".env"


settings = Settings()
