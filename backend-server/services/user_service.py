from database import get_supabase


def build_user_label(nickname: str | None, kakao_id: str | None) -> str:
    clean_nickname = (nickname or "").strip()
    clean_kakao_id = (kakao_id or "").strip()

    if not clean_nickname or clean_nickname == clean_kakao_id:
        clean_nickname = "사용자"

    if clean_kakao_id:
        return f"{clean_nickname} / {clean_kakao_id}"
    return clean_nickname


def normalize_nickname(nickname: str | None, kakao_id: str | None) -> str | None:
    clean_nickname = (nickname or "").strip()
    clean_kakao_id = (kakao_id or "").strip()

    if not clean_nickname:
        return None
    if clean_nickname in ("사용자", "알 수 없음", "unknown", "anonymous"):
        return None
    if clean_kakao_id and clean_nickname == clean_kakao_id:
        return None
    return clean_nickname


async def get_or_create_user(kakao_id: str, nickname: str | None = None) -> dict:
    supabase = get_supabase()
    result = await supabase.table("users").select("id, kakao_id, nickname, role").eq("kakao_id", kakao_id).execute()
    clean_nickname = normalize_nickname(nickname, kakao_id)

    if result.data:
        user = result.data[0]
        current_nickname = (user.get("nickname") or "").strip()
        if clean_nickname and current_nickname != clean_nickname:
            updated = await supabase.table("users").update({
                "nickname": clean_nickname
            }).eq("id", user["id"]).execute()
            if updated.data:
                user = updated.data[0]
        return user

    new_user = await supabase.table("users").upsert({
        "kakao_id": kakao_id,
        "nickname": clean_nickname or kakao_id,
        "role": "user",
    }, on_conflict="kakao_id").execute()

    return new_user.data[0]


async def get_user_by_id(user_id: int) -> dict | None:
    supabase = get_supabase()
    result = await supabase.table("users").select("id, kakao_id, nickname, role").eq("id", user_id).execute()
    return result.data[0] if result.data else None

