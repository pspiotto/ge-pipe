from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    postgres_host: str = "localhost"
    postgres_port: int = 5432
    postgres_user: str = "gepipe"
    postgres_password: str = "gepipe"
    postgres_db: str = "ge_pipe"

    osrs_user_agent: str = "ge-pipe/1.0 (github.com/pspiotto/ge-pipe)"
    osrs_base_url: str = "https://prices.runescape.wiki/api/v1"

    @property
    def postgres_dsn(self) -> str:
        return (
            f"postgresql://{self.postgres_user}:{self.postgres_password}"
            f"@{self.postgres_host}:{self.postgres_port}/{self.postgres_db}"
        )

    model_config = {"env_file": ".env"}


settings = Settings()
