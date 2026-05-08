import os

from fastapi import Header, HTTPException

ADMIN_API_KEY = os.getenv("ADMIN_API_KEY", "").strip()


async def require_admin(x_admin_api_key: str | None = Header(default=None)):
    if not ADMIN_API_KEY:
        return True
    if x_admin_api_key != ADMIN_API_KEY:
        raise HTTPException(status_code=401, detail="관리자 인증이 필요합니다.")
    return True

