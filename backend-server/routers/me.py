from fastapi import APIRouter, Depends, Form

from core.security import get_current_user_payload
from database import get_supabase

router = APIRouter(prefix="/me", tags=["me"])


@router.get("/reports")
async def get_my_reports(current_user: dict = Depends(get_current_user_payload)):
    supabase = get_supabase()
    result = await supabase.table("complaints").select("*").eq(
        "user_id", current_user["user_id"]
    ).order("created_at", desc=True).execute()
    return result.data


@router.post("/push-token")
async def register_my_push_token(
    push_token: str = Form(...),
    current_user: dict = Depends(get_current_user_payload),
):
    supabase = get_supabase()
    await supabase.table("users").update({
        "push_token": push_token.strip() or None
    }).eq("id", current_user["user_id"]).execute()
    return {"success": True}


@router.delete("/push-token")
async def delete_my_push_token(current_user: dict = Depends(get_current_user_payload)):
    supabase = get_supabase()
    await supabase.table("users").update({"push_token": None}).eq("id", current_user["user_id"]).execute()
    return {"success": True}

