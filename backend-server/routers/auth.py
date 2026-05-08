from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Form, HTTPException, status

from core.security import (
    create_access_token,
    create_refresh_token,
    get_current_user_payload,
    hash_refresh_token,
)
from database import get_supabase
from services.kakao_service import fetch_kakao_user
from services.user_service import get_or_create_user, get_user_by_id

router = APIRouter(prefix="/auth", tags=["auth"])


def _public_user(user: dict) -> dict:
    return {
        "id": user["id"],
        "kakao_id": user["kakao_id"],
        "nickname": user.get("nickname") or "사용자",
        "role": user.get("role", "user"),
    }


async def _issue_session(user: dict) -> dict:
    supabase = get_supabase()
    refresh_token, token_hash, expires_at = create_refresh_token()
    await supabase.table("auth_refresh_tokens").insert({
        "user_id": user["id"],
        "token_hash": token_hash,
        "expires_at": expires_at.isoformat(),
    }).execute()
    return {
        "access_token": create_access_token(user),
        "refresh_token": refresh_token,
        "token_type": "bearer",
        "user": _public_user(user),
    }


@router.post("/kakao")
async def login_with_kakao(kakao_access_token: str = Form(...)):
    kakao_user = fetch_kakao_user(kakao_access_token)
    user = await get_or_create_user(kakao_user["kakao_id"], kakao_user.get("nickname"))
    return await _issue_session(user)


@router.post("/refresh")
async def refresh_session(refresh_token: str = Form(...)):
    supabase = get_supabase()
    token_hash = hash_refresh_token(refresh_token)
    result = await supabase.table("auth_refresh_tokens").select(
        "id, user_id, expires_at, revoked_at"
    ).eq("token_hash", token_hash).execute()

    if not result.data:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token")

    stored = result.data[0]
    if stored.get("revoked_at"):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh token revoked")

    expires_at = datetime.fromisoformat(stored["expires_at"].replace("Z", "+00:00"))
    if expires_at < datetime.now(timezone.utc):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh token expired")

    await supabase.table("auth_refresh_tokens").update({
        "revoked_at": datetime.now(timezone.utc).isoformat()
    }).eq("id", stored["id"]).execute()

    user = await get_user_by_id(stored["user_id"])
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found")

    return await _issue_session(user)


@router.post("/logout")
async def logout(
    refresh_token: str = Form(default=""),
    current_user: dict = Depends(get_current_user_payload),
):
    supabase = get_supabase()
    if refresh_token:
        await supabase.table("auth_refresh_tokens").update({
            "revoked_at": datetime.now(timezone.utc).isoformat()
        }).eq("token_hash", hash_refresh_token(refresh_token)).execute()

    await supabase.table("users").update({"push_token": None}).eq("id", current_user["user_id"]).execute()
    return {"success": True}


@router.delete("/withdraw")
async def withdraw(current_user: dict = Depends(get_current_user_payload)):
    supabase = get_supabase()
    now = datetime.now(timezone.utc).isoformat()
    await supabase.table("auth_refresh_tokens").update({"revoked_at": now}).eq("user_id", current_user["user_id"]).execute()
    await supabase.table("users").update({
        "push_token": None,
        "nickname": "탈퇴 사용자",
    }).eq("id", current_user["user_id"]).execute()
    return {"success": True}

