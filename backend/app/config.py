from __future__ import annotations

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="JARDEM_", env_file=".env", extra="ignore")

    database_url: str = ""  # postgresql://...; empty = in-memory only
    redis_url: str = ""  # redis://...; empty = in-process event bus
    jwt_secret: str = "dev-only-change-me"
    demo_pin: str = "1234"  # sign-in PIN for the demo responder and dispatcher accounts
    cors_origins: str = "*"

    strategy: str = "jardem"
    auto_dispatch: bool = True
    seed: int = 7

    tick_s: float = 0.5  # real seconds between engine ticks
    sim_speed: float = 1.0  # simulated seconds per real second
    ambient_calls_per_hour: float = 0.0
    ambient_hotspots: int = 0

    public_app_url: str = "http://localhost:8080/app/citizen/"


def get_settings() -> Settings:
    return Settings()
