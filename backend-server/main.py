# python -m uvicorn main:app --reload 로 서버 실행
import os
import json
import shutil
from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from datetime import datetime, timedelta
from dotenv import load_dotenv

from stt_engine import transcribe_audio
from nlp_engine import classify_complaint
from database import supabase
from messages import ApiMessages

load_dotenv()

app = FastAPI(
    title="AI 민원 접수 시스템",
    description="음성 기반 민원 자동 접수 및 분류 API",
    version="2.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

UPLOAD_DIR = os.path.join(os.path.dirname(__file__), "uploads")
os.makedirs(UPLOAD_DIR, exist_ok=True)


# ─────────────────────────────────────────
# 내부 유틸: 카카오 ID로 users 테이블에서 user_id 조회
# 없으면 자동 생성 (최초 로그인 처리)
# ─────────────────────────────────────────
def get_or_create_user(kakao_id: str, nickname: str = None) -> int:
    result = supabase.table("users").select("id").eq("kakao_id", kakao_id).execute()

    if result.data and len(result.data) > 0:
        return result.data[0]["id"]

    # 신규 유저 생성 (다중/단일 입력 충돌 방지를 위해 리스트로 감쌈)
    new_user = supabase.table("users").insert([{
        "kakao_id": kakao_id,
        "nickname": nickname or kakao_id,
        "role": "user",
        "push_token": None,
        "phone": None
    }]).execute()

    if new_user.data and len(new_user.data) > 0:
        return new_user.data[0]["id"]
        
    raise Exception("User insertion failed: No data returned from Supabase.")


# ─────────────────────────────────────────
# GET /get-reports  —  민원 목록 조회
# ─────────────────────────────────────────
@app.get("/get-reports")
def get_reports():
    """
    민원 전체 목록 조회
    - completed 상태이고 resolved_at 이후 10일 이상 지난 항목은 제외
    """
    result = supabase.table("complaints").select(
        "id, user_id, title, stt_text, lat, lng, category, department, status, created_at, resolved_at"
    ).order("created_at", desc=True).execute()

    now = datetime.utcnow()
    active = []
    for r in result.data:
        if r["status"] == "completed" and r["resolved_at"]:
            resolved_time = datetime.fromisoformat(r["resolved_at"].replace("Z", "+00:00")).replace(tzinfo=None)
            if now - resolved_time > timedelta(days=10):
                continue
        active.append(r)

    return active


# ─────────────────────────────────────────
# GET /get-reports/{user_kakao_id}  —  내 민원만 조회
# ─────────────────────────────────────────
@app.get("/get-reports/{kakao_id}")
def get_my_reports(kakao_id: str):
    """특정 사용자의 민원만 조회"""
    user_result = supabase.table("users").select("id").eq("kakao_id", kakao_id).execute()
    if not user_result.data or len(user_result.data) == 0:
        return []

    user_id = user_result.data[0]["id"]
    result = supabase.table("complaints").select(
        "id, title, stt_text, lat, lng, category, department, status, created_at, resolved_at"
    ).eq("user_id", user_id).order("created_at", desc=True).execute()

    return result.data


# ─────────────────────────────────────────
# POST /resolve-report/{report_id}  —  민원 처리 상태 변경
# ─────────────────────────────────────────
@app.post("/resolve-report/{report_id}")
def resolve_report(report_id: int):
    """민원 처리 완료"""
    try:
        resolved_time = datetime.utcnow().isoformat()
        result = supabase.table("complaints").update({
            "status": "completed",
            "resolved_at": resolved_time
        }).eq("id", report_id).execute()
        
        if result.data:
            return {"status": "success", "message": "민원이 처리 완료되었습니다."}
        else:
            return {"status": "error", "message": "해당 ID의 민원을 찾을 수 없거나 업데이트 오류가 발생했습니다."}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"DB 업데이트 중 오류: {str(e)}")


# ─────────────────────────────────────────
# POST /upload-audio  —  음성 민원 접수 (핵심 API)
# ─────────────────────────────────────────
@app.post("/upload-audio")
async def upload_audio(
    file: UploadFile = File(..., description="음성 파일 (m4a, wav, mp3 등)"),
    lat: float = Form(..., description="위도 (GPS)"),
    lng: float = Form(..., description="경도 (GPS)"),
    kakao_id: str = Form(default="anonymous", description="카카오 로그인 ID (미로그인 시 anonymous)"),
    nickname: str = Form(default=None, description="카카오 닉네임 (선택)")
):
    """
    🎙️ 음성 민원 접수 API

    1. 음성 파일 서버 저장
    2. Whisper STT → 텍스트 변환
    3. GPT-4o mini → 카테고리 / 부서 분류
    4. Supabase complaints 테이블에 저장
    """

    # ── 1. 유저 확인 / 생성
    try:
        user_id = get_or_create_user(kakao_id, nickname)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"사용자 처리 중 오류: {str(e)}")

    # ── 2. 음성 파일 저장
    timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    file_name = f"report_{timestamp}_{file.filename}"
    file_path = os.path.join(UPLOAD_DIR, file_name)

    with open(file_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)

    # ── 3. STT (음성 → 텍스트)
    stt_result = await transcribe_audio(file_path)

    if not stt_result["success"]:
        return {
            "success": False,
            "step": "stt",
            "error": stt_result["error"],
            "message": "음성 인식에 실패했습니다."
        }

    stt_text = stt_result["text"]

    # ── 4. NLP 분류 (텍스트 → 카테고리 / 부서)
    nlp_result = await classify_complaint(stt_text)

    if not nlp_result["success"]:
        return {
            "success": False,
            "step": "nlp",
            "stt_text": stt_text,
            "error": nlp_result["error"],
            "message": "텍스트 분류에 실패했습니다."
        }

    # ── 5. DB 저장
    new_complaint = {
        "user_id":    user_id,
        "stt_text":   stt_text,
        "title":      nlp_result["title"],
        "lat":        lat,
        "lng":        lng,
        "category":   nlp_result["category"],
        "department": nlp_result["department"],
        "status":     "pending",
        "audio_path": file_path,
    }

    try:
        db_result = supabase.table("complaints").insert(new_complaint).execute()
        saved = db_result.data[0]
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"DB 저장 중 오류: {str(e)}")

    return {
        "success": True,
        "message": "민원이 성공적으로 접수되었습니다.",
        "report": saved,
        "stt_text": stt_text
    }


# ─────────────────────────────────────────
# POST /register-user  —  유저 등록 / 푸시 토큰 갱신
# ─────────────────────────────────────────
@app.post("/register-user")
def register_user(
    kakao_id: str = Form(...),
    nickname: str = Form(default=None),
    phone: str = Form(default=None),
    push_token: str = Form(default=None)
):
    """카카오 로그인 후 유저 등록 및 푸시 토큰 저장"""
    existing = supabase.table("users").select("id").eq("kakao_id", kakao_id).execute()

    if existing.data:
        # 기존 유저 → 토큰 업데이트
        update_fields = {}
        if push_token: update_fields["push_token"] = push_token
        if nickname:   update_fields["nickname"]   = nickname
        if phone:      update_fields["phone"]       = phone

        if update_fields:
            supabase.table("users").update(update_fields).eq("kakao_id", kakao_id).execute()

        return {"status": "updated", "user_id": existing.data[0]["id"]}
    else:
        # 신규 유저 생성
        new_user = supabase.table("users").insert({
            "kakao_id":   kakao_id,
            "nickname":   nickname or kakao_id,
            "phone":      phone,
            "push_token": push_token,
            "role":       "user"
        }).execute()
        return {"status": "created", "user_id": new_user.data[0]["id"]}


# ─────────────────────────────────────────
# GET /health  —  서버 상태 확인
# ─────────────────────────────────────────
@app.get("/health")
def health_check():
    """서버 및 DB 연결 상태 확인"""
    try:
        count = supabase.table("complaints").select("id", count="exact").execute()
        db_status = "connected"
        total = count.count if count.count is not None else 0
    except Exception as e:
        db_status = f"error: {str(e)}"
        total = -1

    return {
        "status": "running",
        "db": db_status,
        "total_complaints": total,
        "server_time": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    }