import json
import urllib.error
import urllib.request

from fastapi import HTTPException, status


def fetch_kakao_user(access_token: str) -> dict:
    request = urllib.request.Request(
        "https://kapi.kakao.com/v2/user/me",
        headers={"Authorization": f"Bearer {access_token}"},
    )

    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Kakao token rejected: {e.code}",
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Kakao user lookup failed: {e}",
        )

    kakao_id = str(payload.get("id") or "").strip()
    if not kakao_id:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Kakao user id missing")

    account = payload.get("kakao_account") or {}
    profile = account.get("profile") or {}
    nickname = (
        (profile.get("nickname") or "").strip()
        or ((payload.get("properties") or {}).get("nickname") or "").strip()
        or None
    )
    return {"kakao_id": kakao_id, "nickname": nickname}

