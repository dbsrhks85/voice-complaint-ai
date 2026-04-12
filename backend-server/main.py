# python -m uvicorn main:app --reload 로 서버 실행
import os
import uuid
from contextlib import asynccontextmanager
from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from datetime import datetime, timedelta, timezone
from dotenv import load_dotenv

from database import init_supabase, get_supabase
from stt_engine import transcribe_audio
from nlp_engine import classify_complaint
from messages import ApiMessages

load_dotenv()


# ─────────────────────────────────────────
# FastAPI lifespan — 서버 시작/종료 이벤트
# 서버가 켜질 때 비동기 Supabase 클라이언트를 딱 1번만 초기화
# ─────────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_supabase()   # 🚀 서버 시작: DB 클라이언트 초기화
    yield
    # (필요 시 서버 종료 로직 여기에 추가)


app = FastAPI(
    title="AI 민원 접수 시스템",
    description="음성 기반 민원 자동 접수 및 분류 API",
    version="3.0.0",
    lifespan=lifespan
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # TODO: 배포 시 실제 도메인으로 제한 필요 (보안)
    allow_methods=["*"],
    allow_headers=["*"],
)

UPLOAD_DIR = os.path.join(os.path.dirname(__file__), "uploads")
os.makedirs(UPLOAD_DIR, exist_ok=True)

MAX_FILE_SIZE = 25 * 1024 * 1024  # 25MB


# ─────────────────────────────────────────
# 내부 유틸: 카카오 ID로 users 테이블에서 user_id 조회
# 없으면 자동 생성 (최초 로그인 처리)
# ─────────────────────────────────────────
async def get_or_create_user(kakao_id: str, nickname: str = None) -> int:
    supabase = get_supabase()

    result = await supabase.table("users").select("id").eq("kakao_id", kakao_id).execute()

    if result.data and len(result.data) > 0:
        return result.data[0]["id"]

    # 신규 유저 생성 (upsert로 Race Condition 방지)
    new_user = await supabase.table("users").upsert({
        "kakao_id":   kakao_id,
        "nickname":   nickname or kakao_id,
        "role":       "user",
        "push_token": None,
        "phone":      None
    }, on_conflict="kakao_id").execute()

    if new_user.data and len(new_user.data) > 0:
        return new_user.data[0]["id"]

    raise Exception("유저 생성 실패: Supabase에서 데이터가 반환되지 않았습니다.")


# ─────────────────────────────────────────
# GET /get-reports  —  민원 목록 조회
# ─────────────────────────────────────────
@app.get("/get-reports")
async def get_reports():
    """
    민원 전체 목록 조회
    - completed 상태이고 resolved_at 이후 10일 이상 지난 항목은 제외
    """
    supabase = get_supabase()

    result = await supabase.table("complaints").select(
        "id, user_id, title, stt_text, lat, lng, category, department, status, created_at, resolved_at"
    ).order("created_at", desc=True).execute()

    now = datetime.now(timezone.utc)
    active = []
    for r in result.data:
        if r["status"] == "completed" and r["resolved_at"]:
            resolved_time = datetime.fromisoformat(r["resolved_at"].replace("Z", "+00:00"))
            if now - resolved_time > timedelta(days=10):
                continue
        active.append(r)

    return active


# ─────────────────────────────────────────
# GET /get-reports/{kakao_id}  —  내 민원만 조회
# ─────────────────────────────────────────
@app.get("/get-reports/{kakao_id}")
async def get_my_reports(kakao_id: str):
    """특정 사용자의 민원만 조회"""
    supabase = get_supabase()

    user_result = await supabase.table("users").select("id").eq("kakao_id", kakao_id).execute()
    if not user_result.data or len(user_result.data) == 0:
        return []

    user_id = user_result.data[0]["id"]
    result = await supabase.table("complaints").select(
        "id, title, stt_text, lat, lng, category, department, status, created_at, resolved_at"
    ).eq("user_id", user_id).order("created_at", desc=True).execute()

    return result.data


# ─────────────────────────────────────────
# POST /resolve-report/{report_id}  —  민원 처리 상태 변경
# ─────────────────────────────────────────
@app.post("/resolve-report/{report_id}")
async def resolve_report(report_id: int):
    """민원 처리 완료"""
    supabase = get_supabase()

    try:
        result = await supabase.table("complaints").update({
            "status": "completed",
            "resolved_at": datetime.now(timezone.utc).isoformat()
        }).eq("id", report_id).execute()

        if not result.data:
            raise HTTPException(status_code=404, detail=ApiMessages.REPORT_NOT_FOUND)

        return {"status": ApiMessages.RESOLVE_SUCCESS}

    except HTTPException:
        raise
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
    supabase = get_supabase()

    # ── 0. 파일 크기 검증 + async read
    content = await file.read()
    if len(content) > MAX_FILE_SIZE:
        raise HTTPException(status_code=413, detail="파일 크기는 25MB를 초과할 수 없습니다.")

    # ── 1. 유저 확인 / 생성
    try:
        user_id = await get_or_create_user(kakao_id, nickname)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"사용자 처리 중 오류: {str(e)}")

    # ── 2. 음성 파일 저장 (UUID 파일명으로 Path Traversal 방지)
    timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    ext = os.path.splitext(file.filename or "")[-1].lower() or ".m4a"
    file_name = f"report_{timestamp}_{uuid.uuid4().hex}{ext}"
    file_path = os.path.join(UPLOAD_DIR, file_name)

    with open(file_path, "wb") as buffer:
        buffer.write(content)

    # ── 3. STT (음성 → 텍스트)
    stt_result = await transcribe_audio(file_path)

    if not stt_result["success"]:
        if os.path.exists(file_path):
            os.remove(file_path)
        return {
            "success": False,
            "step": "stt",
            "error": stt_result["error"],
            "message": ApiMessages.STT_FAILED
        }

    stt_text = stt_result["text"]

    # ── 4. NLP 분류 (텍스트 → 카테고리 / 부서)
    nlp_result = await classify_complaint(stt_text)

    if not nlp_result["success"]:
        if os.path.exists(file_path):
            os.remove(file_path)
        return {
            "success": False,
            "step": "nlp",
            "stt_text": stt_text,
            "error": nlp_result["error"],
            "message": ApiMessages.NLP_FAILED
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
        db_result = await supabase.table("complaints").insert(new_complaint).execute()
        saved = db_result.data[0]
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"DB 저장 중 오류: {str(e)}")

    return {
        "success": True,
        "message": ApiMessages.REPORT_SUCCESS,
        "report": saved,
        "stt_text": stt_text
    }


# ─────────────────────────────────────────
# POST /register-user  —  유저 등록 / 푸시 토큰 갱신
# ─────────────────────────────────────────
@app.post("/register-user")
async def register_user(
    kakao_id: str = Form(...),
    nickname: str = Form(default=None),
    phone: str = Form(default=None),
    push_token: str = Form(default=None)
):
    """카카오 로그인 후 유저 등록 및 푸시 토큰 저장"""
    supabase = get_supabase()

    existing = await supabase.table("users").select("id").eq("kakao_id", kakao_id).execute()

    if existing.data:
        update_fields = {}
        if push_token: update_fields["push_token"] = push_token
        if nickname:   update_fields["nickname"]   = nickname
        if phone:      update_fields["phone"]       = phone

        if update_fields:
            await supabase.table("users").update(update_fields).eq("kakao_id", kakao_id).execute()

        return {"status": "updated", "user_id": existing.data[0]["id"]}
    else:
        new_user = await supabase.table("users").insert({
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
async def health_check():
    """서버 및 DB 연결 상태 확인"""
    try:
        supabase = get_supabase()
        count = await supabase.table("complaints").select("id", count="exact").execute()
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