# ============================================================
# 🚀 서버 실행 가이드 (backend-server/ 폴더에서 실행)
# ============================================================
#
# 1️⃣  가상환경 활성화 (최초 1회 또는 터미널 새로 열 때마다)
#     source venv/bin/activate
#
# 2️⃣  서버 실행
#     python -m uvicorn main:app --reload
#
# 3️⃣  서버 종료
#     Ctrl + C
#
# 4️⃣  가상환경 비활성화 (선택사항)
#     deactivate
#
# 📌 서버 실행 후 확인
#     - API 문서  : http://127.0.0.1:8000/docs
#     - 상태 확인 : http://127.0.0.1:8000/health
# ============================================================
import os
import uuid
import json
import zipfile
import io
import urllib.parse
from datetime import datetime, timezone
from contextlib import asynccontextmanager
from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import StreamingResponse
from datetime import datetime, timedelta, timezone
from dotenv import load_dotenv

from database import init_supabase, get_supabase
from stt_engine import transcribe_audio
from nlp_engine import classify_complaint
from messages import ApiMessages

# .env 파일 로드
load_dotenv()

# ─────────────────────────────────────────
# FastAPI lifespan — 서버 시작/종료 이벤트
# ─────────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_supabase()   # 🚀 서버 시작: DB 클라이언트 초기화
    yield

app = FastAPI(
    title="AI 민원 접수 시스템",
    description="음성 기반 민원 자동 접수 및 분류 API",
    version="3.1.0",
    lifespan=lifespan
)

# CORS 설정
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# 업로드 디렉토리 및 설정
UPLOAD_DIR = os.path.join(os.path.dirname(__file__), "uploads")
os.makedirs(UPLOAD_DIR, exist_ok=True)
MAX_FILE_SIZE = 25 * 1024 * 1024  # 25MB

# 정적 파일 서빙 (첨부파일 열람용)
app.mount("/uploads", StaticFiles(directory=UPLOAD_DIR), name="uploads")

# ─────────────────────────────────────────
# 내부 유틸: 유저 관리
# ─────────────────────────────────────────
async def get_or_create_user(kakao_id: str, nickname: str = None) -> int:
    supabase = get_supabase()
    result = await supabase.table("users").select("id").eq("kakao_id", kakao_id).execute()

    if result.data and len(result.data) > 0:
        return result.data[0]["id"]

    new_user = await supabase.table("users").upsert({
        "kakao_id": kakao_id,
        "nickname": nickname or kakao_id,
        "role": "user",
    }, on_conflict="kakao_id").execute()

    return new_user.data[0]["id"]

# ─────────────────────────────────────────
# API 엔드포인트
# ─────────────────────────────────────────

@app.get("/health")
async def health_check():
    """서버 및 DB 상태 확인"""
    try:
        supabase = get_supabase()
        count = await supabase.table("complaints").select("id", count="exact").execute()
        return {
            "status": "running",
            "db": "connected",
            "total_complaints": count.count,
            "server_time": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        }
    except Exception as e:
        return {"status": "running", "db": f"error: {str(e)}"}

@app.get("/get-reports")
async def get_reports():
    """민원 전체 목록 조회 (작성자 닉네임 포함)"""
    supabase = get_supabase()
    # users 테이블과 join하여 nickname 가져오기
    result = await supabase.table("complaints").select("*, users(nickname)").order("created_at", desc=True).execute()

    now = datetime.now(timezone.utc)
    active = []
    for r in result.data:
        # 데이터 정규화: users(nickname)을 r["nickname"]으로 평탄화
        if "users" in r and r["users"]:
            r["nickname"] = r["users"].get("nickname", "알 수 없음")
        else:
            r["nickname"] = "알 수 없음"

        if r["status"] == "completed" and r["resolved_at"]:
            resolved_time = datetime.fromisoformat(r["resolved_at"].replace("Z", "+00:00"))
            if now - resolved_time > timedelta(days=10):
                continue
        active.append(r)
    return active

@app.get("/get-departments")
async def get_departments():
    """담당 부서 목록 조회 (관리자 웹 필터/업무 안내용)"""
    supabase = get_supabase()
    result = await supabase.table("departments").select("*").order("id").execute()
    return result.data

@app.get("/get-reports/{kakao_id}")
async def get_my_reports(kakao_id: str):
    """내 민원만 조회"""
    supabase = get_supabase()
    user_res = await supabase.table("users").select("id").eq("kakao_id", kakao_id).execute()
    if not user_res.data: return []

    user_id = user_res.data[0]["id"]
    result = await supabase.table("complaints").select("*").eq("user_id", user_id).order("created_at", desc=True).execute()
    return result.data

@app.post("/update-status/{report_id}")
async def update_status(
    report_id: int, 
    status: str = Form(...),
    rejection_reason: str = Form(None)
):
    """민원 상태 변경 (pending, processing, completed, rejected)"""
    if status not in ["pending", "processing", "completed", "rejected"]:
        raise HTTPException(status_code=400, detail="지원하지 않는 상태값입니다.")

    supabase = get_supabase()
    update_data = {"status": status}
    
    if status in ["processing", "completed", "rejected"]:
        update_data["resolved_at"] = datetime.now(timezone.utc).isoformat()
        
    if status == "rejected" and rejection_reason:
        update_data["rejection_reason"] = rejection_reason

    result = await supabase.table("complaints").update(update_data).eq("id", report_id).execute()
    if not result.data:
        raise HTTPException(status_code=404, detail=ApiMessages.REPORT_NOT_FOUND)
    return {"success": True, "status": status}

@app.post("/resolve-report/{report_id}")
async def resolve_report(report_id: int):
    """관리자 웹 호환용: 민원을 처리 완료 상태로 변경"""
    supabase = get_supabase()
    update_data = {
        "status": "completed",
        "resolved_at": datetime.now(timezone.utc).isoformat()
    }

    result = await supabase.table("complaints").update(update_data).eq("id", report_id).execute()
    if not result.data:
        raise HTTPException(status_code=404, detail=ApiMessages.REPORT_NOT_FOUND)
    return {"success": True, "status": "completed"}

@app.post("/stt-only")
async def stt_only(file: UploadFile = File(...)):
    """음성 전송 시 STT 결과와 NLP 분류 제안 반환"""
    content = await file.read()
    ext = os.path.splitext(file.filename or "")[-1].lower() or ".m4a"
    file_path = os.path.join(UPLOAD_DIR, f"tmp_{uuid.uuid4().hex}{ext}")

    with open(file_path, "wb") as f:
        f.write(content)

    stt_result = await transcribe_audio(file_path)
    if os.path.exists(file_path): os.remove(file_path)

    if not stt_result["success"]:
        raise HTTPException(status_code=500, detail=ApiMessages.STT_FAILED)

    nlp_suggestion = await classify_complaint(stt_result["text"])
    return {
        "success": True,
        "stt_text": stt_result["text"],
        "nlp_suggestion": nlp_suggestion
    }

@app.post("/submit-complaint")
async def submit_complaint(
    stt_text: str = Form(...),
    lat: float = Form(None),
    lng: float = Form(None),
    address: str = Form(None),
    kakao_id: str = Form(default="anonymous"),
    nickname: str = Form(default=None),
    title: str = Form(None),
    category: str = Form(None),
    department: str = Form(None),
    complaint_type: str = Form("field"),
    attachment_note: str = Form(None),
    attachments: list[UploadFile] = File(default=[])
):
    """최종 민원 제출 및 DB 저장"""
    supabase = get_supabase()
    if complaint_type == "admin_task":
        complaint_type = "admin"
    if complaint_type not in ["field", "admin"]:
        complaint_type = "field"

    # 1. 유저 ID 확보
    user_id = await get_or_create_user(kakao_id, nickname)

    # 2. 첨부파일 저장
    saved_urls = []
    for file in attachments:
        if file.filename:
            unique_name = f"at_{datetime.now().strftime('%Y%m%d')}_{uuid.uuid4().hex[:8]}_{file.filename}"
            file_path = os.path.join(UPLOAD_DIR, unique_name)
            content = await file.read()
            with open(file_path, "wb") as f:
                f.write(content)
            # 프론트엔드에서 쉽게 접근할 수 있도록 파일명(또는 상대경로)만 저장
            saved_urls.append(unique_name)

    # 3. 데이터 보완 (NLP)
    if not (title and category and department):
        nlp = await classify_complaint(stt_text)
        title = title or nlp.get("title", "제목 없음")
        category = category or nlp.get("category", "기타")
        department = department or nlp.get("department", "해당 없음")

    # 4. DB Insert 객체 생성
    complaint_data = {
        "user_id": user_id,
        "stt_text": stt_text,
        "title": title,
        "lat": lat,
        "lng": lng,
        "address": address,
        "complaint_type": complaint_type,
        "category": category,
        "department": department,
        "status": "pending",
        "attachment_urls": saved_urls,
        "attachment_note": attachment_note
    }

    # 5. DB 저장 및 로그 기록
    try:
        db_res = await supabase.table("complaints").insert(complaint_data).execute()
        
        # 테스트 로그 저장 (선택 사항)
        log_path = os.path.join(os.path.dirname(__file__), "test_results", f"log_{uuid.uuid4().hex[:8]}.json")
        os.makedirs(os.path.dirname(log_path), exist_ok=True)
        with open(log_path, "w", encoding="utf-8") as f:
            json.dump(complaint_data, f, ensure_ascii=False, indent=2)

        return {
            "success": True,
            "message": ApiMessages.REPORT_SUCCESS,
            "report": db_res.data[0]
        }
    except Exception as e:
        print(f"DB Insert Error: {e}")
        raise HTTPException(status_code=500, detail=f"데이터 저장 실패: {str(e)}")

@app.get("/download-attachments/{report_id}")
async def download_attachments(report_id: int):
    """특정 민원의 모든 첨부파일을 ZIP으로 압축하여 다운로드"""
    supabase = get_supabase()
    
    # 1. 민원 및 유저 정보 조회
    result = await supabase.table("complaints").select("*, users(nickname)").eq("id", report_id).execute()
    if not result.data:
        raise HTTPException(status_code=404, detail="민원을 찾을 수 없습니다.")
    
    report = result.data[0]
    nickname = "unknown"
    if "users" in report and report["users"]:
        nickname = report["users"].get("nickname") or "unknown"
    
    attachment_urls = report.get("attachment_urls", [])
    if not attachment_urls:
        raise HTTPException(status_code=400, detail="첨부파일이 없습니다.")

    try:
        # 2. ZIP 파일 생성 (메모리 내)
        zip_buffer = io.BytesIO()
        
        # 날짜 및 닉네임 정리 (None 또는 숫자형 대비 str 변환)
        date_prefix = datetime.now().strftime("%y%m%d")
        nickname_str = str(nickname)
        safe_nickname = "".join([c for c in nickname_str if c.isalnum() or c in (" ", "-", "_")]).strip() or "unknown"

        files_found = 0
        with zipfile.ZipFile(zip_buffer, "w", zipfile.ZIP_DEFLATED) as zip_file:
            for file_info in attachment_urls:
                if not file_info:
                    continue
                
                filename = os.path.basename(file_info)
                # 1순위: 현재 UPLOAD_DIR 확인
                file_path = os.path.join(UPLOAD_DIR, filename)
                
                # 압축 파일 내 저장될 이름 (날짜_닉네임_파일명)
                arc_name = f"{date_prefix}_{safe_nickname}_{filename}"
                
                if os.path.exists(file_path):
                    zip_file.write(file_path, arcname=arc_name)
                    files_found += 1
                elif os.path.exists(file_info): # 2순위: DB에 저장된 원래 절대 경로 확인 (호환성용)
                    zip_file.write(file_info, arcname=arc_name)
                    files_found += 1
                else:
                    print(f"Warning: File not found on disk: {file_path} or {file_info}")

        if files_found == 0:
            raise HTTPException(status_code=404, detail=f"서버에서 실제 파일을 찾을 수 없습니다. (ID: {report_id})")

        zip_buffer.seek(0)
        
        # 다운로드 파일명 설정 및 RFC 5987 기반 인코딩 (브라우저 한글 깨짐 방지)
        download_name = f"{date_prefix}_{safe_nickname}_첨부파일.zip"
        encoded_name = urllib.parse.quote(download_name)
        
        return StreamingResponse(
            zip_buffer,
            media_type="application/zip",
            headers={
                "Content-Disposition": f"attachment; filename*=UTF-8''{encoded_name}"
            }
        )
    except HTTPException:
        raise
    except Exception as e:
        print(f"Download Error for Report ID {report_id}: {str(e)}")
        raise HTTPException(status_code=500, detail=f"첨부파일 압축 생성 중 오류가 발생했습니다: {str(e)}")
