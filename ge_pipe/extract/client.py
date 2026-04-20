import httpx
from ge_pipe.settings import settings


def get_client() -> httpx.Client:
    return httpx.Client(
        base_url=settings.osrs_base_url,
        headers={"User-Agent": settings.osrs_user_agent},
        timeout=30.0,
    )
