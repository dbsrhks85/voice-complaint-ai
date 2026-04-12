import os
from supabase import acreate_client, AsyncClient
from dotenv import load_dotenv

load_dotenv(encoding="utf-8")

SUPABASE_URL: str = os.getenv("SUPABASE_URL", "")
SUPABASE_KEY: str = os.getenv("SUPABASE_KEY", "")

if not SUPABASE_URL or not SUPABASE_KEY:
    raise ValueError("SUPABASE_URL or SUPABASE_KEY is not set in .env")

# 비동기 클라이언트 모듈 변수 (서버 시작 시 init_supabase()로 초기화)
_supabase: AsyncClient | None = None


async def init_supabase() -> None:
    """FastAPI 서버 시작(lifespan) 시 비동기 Supabase 클라이언트 1회 초기화"""
    global _supabase
    _supabase = await acreate_client(SUPABASE_URL, SUPABASE_KEY)


def get_supabase() -> AsyncClient:
    """초기화된 비동기 Supabase 클라이언트 반환"""
    if _supabase is None:
        raise RuntimeError(
            "Supabase 클라이언트 미초기화: 서버 lifespan에서 init_supabase() 호출 필요"
        )
    return _supabase
