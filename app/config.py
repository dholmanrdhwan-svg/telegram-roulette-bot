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
