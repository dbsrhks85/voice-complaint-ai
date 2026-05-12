# ============================================================
# 🚀 서버 실행 가이드 (backend-server/ 폴더에서 실행)
# ============================================================
#
# 1️⃣  가상환경 활성화 (최초 1회 또는 터미널 새로 열 때마다)
#     source venv/bin/activate
#
# 2️⃣  서버 실행
#     python -m uvicorn main:app --host 0.0.0.0 --reload
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
import asyncio
import math
import urllib.parse
import urllib.request
import urllib.error
from contextlib import asynccontextmanager
from fastapi import FastAPI, UploadFile, File, Form, HTTPException, Depends, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import StreamingResponse
from sse_starlette.sse import EventSourceResponse
from datetime import datetime, timedelta, timezone
from dotenv import load_dotenv

from database import init_supabase, get_supabase
from stt_engine import transcribe_audio
from nlp_engine import classify_complaint
from messages import ApiMessages
from core.admin_auth import require_admin
from core.security import get_current_user_payload
from routers.admin_auth import router as admin_auth_router
from routers.auth import router as auth_router
from routers.me import router as me_router

try:
    import firebase_admin
    from firebase_admin import credentials, messaging
except ImportError:
    firebase_admin = None
    credentials = None
    messaging = None

# .env 파일 로드
load_dotenv()

# ─────────────────────────────────────────
# FastAPI lifespan — 서버 시작/종료 이벤트
# ─────────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_supabase()   # 🚀 서버 시작: DB 클라이언트 초기화
    init_firebase_admin()   # 🔔 푸쉬 알림용 Firebase Admin 초기화
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

app.include_router(auth_router)
app.include_router(me_router)
app.include_router(admin_auth_router)

# 업로드 디렉토리 및 설정
UPLOAD_DIR = os.path.join(os.path.dirname(__file__), "uploads")
os.makedirs(UPLOAD_DIR, exist_ok=True)
MAX_FILE_SIZE = 25 * 1024 * 1024  # 25MB

# 정적 파일 서빙 (첨부파일 열람용)
app.mount("/uploads", StaticFiles(directory=UPLOAD_DIR), name="uploads")

# ─────────────────────────────────────────
# SSE 브로드캐스터 — 관리자 실시간 갱신
# ─────────────────────────────────────────
_sse_queues: list[asyncio.Queue] = []  # 연결된 관리자 클라이언트 큐 목록

async def broadcast_new_complaint():
    """새 민원 접수 시 모든 관리자 클라이언트에 이벤트 브로드캐스트"""
    dead = []
    for q in _sse_queues:
        try:
            await q.put("refresh")
        except Exception:
            dead.append(q)
    for q in dead:
        _sse_queues.remove(q)
    print(f"[sse] 브로드캐스트 완료: {len(_sse_queues)}개 클라이언트")


KAKAO_REST_API_KEY = (
    os.getenv("KAKAO_REST_API_KEY")
    or os.getenv("KAKAO_API_KEY")
    or os.getenv("KAKAO_MAP_REST_API_KEY")
)
FIREBASE_CREDENTIALS_PATH = os.getenv("FIREBASE_CREDENTIALS_PATH")

# ─────────────────────────────────────────
# 내부 유틸: 유저 관리
# ─────────────────────────────────────────
def build_user_label(nickname: str | None, kakao_id: str | None) -> str:
    """관리자 화면용 민원인 표시명 생성"""
    clean_nickname = (nickname or "").strip()
    clean_kakao_id = (kakao_id or "").strip()

    if not clean_nickname or clean_nickname == clean_kakao_id:
        clean_nickname = "사용자"

    if clean_kakao_id:
        return f"{clean_nickname} / {clean_kakao_id}"
    return clean_nickname


def normalize_nickname(nickname: str | None, kakao_id: str | None) -> str | None:
    """카카오 닉네임으로 보기 어려운 fallback 값은 저장/갱신에서 제외"""
    clean_nickname = (nickname or "").strip()
    clean_kakao_id = (kakao_id or "").strip()

    if not clean_nickname:
        return None
    if clean_nickname in ("사용자", "알 수 없음", "unknown", "anonymous"):
        return None
    if clean_kakao_id and clean_nickname == clean_kakao_id:
        return None
    return clean_nickname


async def get_or_create_user(kakao_id: str, nickname: str = None) -> int:
    supabase = get_supabase()
    result = await supabase.table("users").select("id, nickname").eq("kakao_id", kakao_id).execute()
    clean_nickname = normalize_nickname(nickname, kakao_id)

    if result.data and len(result.data) > 0:
        user = result.data[0]
        current_nickname = (user.get("nickname") or "").strip()
        if clean_nickname and current_nickname != clean_nickname:
            await supabase.table("users").update({
                "nickname": clean_nickname
            }).eq("id", user["id"]).execute()
        return user["id"]

    new_user = await supabase.table("users").upsert({
        "kakao_id": kakao_id,
        "nickname": clean_nickname or kakao_id,
        "role": "user",
    }, on_conflict="kakao_id").execute()

    return new_user.data[0]["id"]


def init_firebase_admin() -> bool:
    """Firebase Admin SDK 초기화. 설정이 없으면 푸쉬만 비활성화."""
    if firebase_admin is None or credentials is None:
        print("[push] firebase-admin package is not installed. Push disabled.")
        return False
    if firebase_admin._apps:
        return True
    if not FIREBASE_CREDENTIALS_PATH:
        print("[push] FIREBASE_CREDENTIALS_PATH is not set. Push disabled.")
        return False
    if not os.path.exists(FIREBASE_CREDENTIALS_PATH):
        print(f"[push] Firebase credentials not found: {FIREBASE_CREDENTIALS_PATH}")
        return False

    cred = credentials.Certificate(FIREBASE_CREDENTIALS_PATH)
    firebase_admin.initialize_app(cred)
    print("[push] Firebase Admin initialized.")
    return True


def status_push_message(status: str, title: str | None, rejection_reason: str | None = None):
    complaint_title = title or "접수하신 민원"
    if status == "processing":
        return (
            "민원이 수락되었습니다",
            f"'{complaint_title}' 민원이 처리 중으로 변경되었습니다.",
        )
    if status == "completed":
        return (
            "민원 처리가 완료되었습니다",
            f"'{complaint_title}' 민원 처리가 완료되었습니다.",
        )
    if status == "rejected":
        reason = rejection_reason or "사유 미입력"
        return (
            "민원이 반려되었습니다",
            f"'{complaint_title}' 민원이 반려되었습니다. 사유: {reason}",
        )
    return ("민원 상태가 변경되었습니다", f"'{complaint_title}' 상태가 변경되었습니다.")


def send_push_to_token(push_token: str, title: str, body: str, data: dict | None = None) -> str | None:
    """단일 FCM 토큰으로 알림 발송"""
    if not push_token:
        return None
    if not init_firebase_admin() or messaging is None:
        return None

    message = messaging.Message(
        notification=messaging.Notification(title=title, body=body),
        data={k: str(v) for k, v in (data or {}).items() if v is not None},
        android=messaging.AndroidConfig(
            priority="high",
        ),
        token=push_token,
    )
    return messaging.send(message)


async def send_status_push(report_id: int, status: str, rejection_reason: str | None = None):
    """민원 상태 변경 결과를 작성자 기기로 푸쉬 발송"""
    try:
        supabase = get_supabase()
        report_res = await supabase.table("complaints").select(
            "id, title, user_id, users(push_token)"
        ).eq("id", report_id).execute()
        if not report_res.data:
            return

        report = report_res.data[0]
        user = report.get("users") or {}
        push_token = user.get("push_token")
        if not push_token:
            print(f"[push] no push token for report_id={report_id}")
            return

        push_title, push_body = status_push_message(
            status,
            report.get("title"),
            rejection_reason,
        )
        response = await asyncio.to_thread(
            send_push_to_token,
            push_token,
            push_title,
            push_body,
            {
                "type": "complaint_status",
                "report_id": report_id,
                "status": status,
                "rejection_reason": rejection_reason or "",
            },
        )
        print(f"[push] sent report_id={report_id} status={status}: {response}")
    except Exception as e:
        print(f"[push] failed report_id={report_id} status={status}: {e}")


def reverse_geocode_address(lat: float, lng: float) -> str | None:
    """카카오 로컬 API로 좌표를 주소 문자열로 변환"""
    if not KAKAO_REST_API_KEY:
        return None

    query = urllib.parse.urlencode({"x": lng, "y": lat})
    url = f"https://dapi.kakao.com/v2/local/geo/coord2address.json?{query}"
    request = urllib.request.Request(
        url,
        headers={"Authorization": f"KakaoAK {KAKAO_REST_API_KEY}"}
    )

    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        error_body = e.read().decode("utf-8", errors="ignore")
        print(f"[reverse_geocode] Kakao API error {e.code}: {error_body}")
        return None
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as e:
        print(f"[reverse_geocode] request failed: {e}")
        return None

    documents = payload.get("documents") or []
    if not documents:
        return None

    first = documents[0]
    road_address = first.get("road_address") or {}
    address = first.get("address") or {}
    return road_address.get("address_name") or address.get("address_name")


def is_valid_lat_lng(lat: float | None, lng: float | None) -> bool:
    return (
        lat is not None
        and lng is not None
        and math.isfinite(lat)
        and math.isfinite(lng)
        and -90 <= lat <= 90
        and -180 <= lng <= 180
    )


def validate_optional_lat_lng(lat: float | None, lng: float | None) -> None:
    if lat is None and lng is None:
        return
    if lat is None or lng is None:
        raise HTTPException(status_code=400, detail="lat/lng는 함께 전달되어야 합니다.")
    if not is_valid_lat_lng(lat, lng):
        raise HTTPException(status_code=400, detail="유효하지 않은 좌표입니다.")

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
async def get_reports(_: bool = Depends(require_admin)):
    """민원 전체 목록 조회 (작성자 닉네임 포함)"""
    supabase = get_supabase()
    # users 테이블과 join하여 관리자 표시용 민원인 정보를 가져오기
    result = await supabase.table("complaints").select("*, users(id, nickname, kakao_id)").order("created_at", desc=True).execute()

    now = datetime.now(timezone.utc)
    active = []
    for r in result.data:
        # 데이터 정규화: users 정보를 관리자 웹에서 쓰기 쉽게 평탄화
        user = r.get("users") or {}
        r["user_db_id"] = user.get("id")
        r["kakao_id"] = user.get("kakao_id")
        r["nickname"] = user.get("nickname") or "사용자"
        r["user_label"] = build_user_label(r["nickname"], r["kakao_id"])

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

@app.post("/admin/add-department")
async def add_department(
    key: str = Form(...),
    label: str = Form(...),
    phone: str = Form(None),
    color: str = Form(None),
    keywords: str = Form(None), # 쉼표로 구분된 문자열
    tasks: str = Form(None),    # 쉼표로 구분된 문자열
    _: bool = Depends(require_admin),
):
    """부서 추가 (관리자 전용)"""
    supabase = get_supabase()
    
    # 쉼표 구분 문자열을 배열로 변환
    keyword_list = [k.strip() for k in keywords.split(",")] if keywords else []
    task_list = [t.strip() for t in tasks.split(",")] if tasks else []

    try:
        result = await supabase.table("departments").insert({
            "key": key,
            "label": label,
            "phone": phone,
            "color": color,
            "keywords": keyword_list,
            "tasks": task_list
        }).execute()
        
        if not result.data:
            raise HTTPException(status_code=500, detail="부서 추가에 실패했습니다.")
            
        return {"success": True, "data": result.data[0]}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"DB 오류: {str(e)}")

@app.delete("/admin/delete-department/{dept_id}")
async def delete_department(
    dept_id: int, 
    reassign_to: str = Query(None), # 재배정할 부서의 Key
    _: bool = Depends(require_admin)
):
    """부서 삭제 및 관련 민원 재배정 (관리자 전용)"""
    supabase = get_supabase()
    try:
        # 1. 삭제할 부서 정보 조회
        dept_res = await supabase.table("departments").select("key").eq("id", dept_id).execute()
        if not dept_res.data:
            raise HTTPException(status_code=404, detail="부서를 찾을 수 없습니다.")
        
        old_key = dept_res.data[0]["key"]

        # 2. 민원 재배정 (reassign_to가 지정된 경우)
        if reassign_to:
            await supabase.table("complaints").update({"department": reassign_to}).eq("department", old_key).execute()
        
        # 3. 부서 삭제
        result = await supabase.table("departments").delete().eq("id", dept_id).execute()
        
        if not result.data:
            # FK 제약 등으로 삭제 실패 시 (reassign_to가 없거나 실패한 경우)
            raise HTTPException(status_code=400, detail="부서 삭제에 실패했습니다. 해당 부서의 민원을 먼저 모두 이관해야 합니다.")
            
        return {"success": True}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"DB 오류: {str(e)}")

@app.get("/reverse-geocode")
async def reverse_geocode(lat: float, lng: float):
    """좌표를 사람이 읽을 수 있는 주소로 변환"""
    if not is_valid_lat_lng(lat, lng):
        raise HTTPException(status_code=400, detail="유효하지 않은 좌표입니다.")
    if not KAKAO_REST_API_KEY:
        raise HTTPException(status_code=500, detail="KAKAO_REST_API_KEY가 설정되지 않았습니다.")

    address = reverse_geocode_address(lat, lng)
    if not address:
        return {"success": False, "address": None}
    return {"success": True, "address": address}

@app.get("/get-reports/{kakao_id}")
async def get_my_reports(
    kakao_id: str,
    current_user: dict = Depends(get_current_user_payload),
):
    """내 민원만 조회 (legacy path: token 사용자와 kakao_id가 일치해야 함)"""
    if current_user.get("kakao_id") != kakao_id:
        raise HTTPException(status_code=403, detail="다른 사용자의 민원을 조회할 수 없습니다.")

    supabase = get_supabase()
    user_res = await supabase.table("users").select("id").eq("kakao_id", kakao_id).execute()
    if not user_res.data: return []

    user_id = user_res.data[0]["id"]
    result = await supabase.table("complaints").select("*").eq("user_id", user_id).order("created_at", desc=True).execute()
    return result.data

@app.post("/register-push-token")
async def register_push_token(
    push_token: str = Form(...),
    nickname: str = Form(default=None),
    current_user: dict = Depends(get_current_user_payload),
):
    """사용자 기기의 FCM push token 저장"""
    if not push_token.strip():
        raise HTTPException(status_code=400, detail="push_token이 필요합니다.")

    supabase = get_supabase()
    user_id = current_user["user_id"]
    result = await supabase.table("users").update({
        "push_token": push_token.strip(),
        **({"nickname": normalize_nickname(nickname, current_user.get("kakao_id"))} if normalize_nickname(nickname, current_user.get("kakao_id")) else {}),
    }).eq("id", user_id).execute()

    if not result.data:
        raise HTTPException(status_code=404, detail="사용자를 찾을 수 없습니다.")
    return {"success": True}

@app.post("/update-status/{report_id}")
async def update_status(
    report_id: int, 
    status: str = Form(...),
    rejection_reason: str = Form(None),
    _: bool = Depends(require_admin),
):
    """민원 상태 변경 (pending, processing, completed, rejected)"""
    if status not in ["pending", "processing", "completed", "rejected"]:
        raise HTTPException(status_code=400, detail="지원하지 않는 상태값입니다.")
    if status == "rejected" and not rejection_reason:
        raise HTTPException(status_code=400, detail="반려 사유가 필요합니다.")

    supabase = get_supabase()
    update_data = {"status": status}

    now = datetime.now(timezone.utc).isoformat()
    if status == "processing":
        update_data["accepted_at"] = now
    elif status == "completed":
        update_data["resolved_at"] = now
    elif status == "rejected":
        update_data["rejected_at"] = now
        update_data["rejection_reason"] = rejection_reason

    result = await supabase.table("complaints").update(update_data).eq("id", report_id).execute()
    if not result.data:
        raise HTTPException(status_code=404, detail=ApiMessages.REPORT_NOT_FOUND)

    if status in ["processing", "completed", "rejected"]:
        await send_status_push(report_id, status, rejection_reason)
    return {"success": True, "status": status}

@app.post("/resolve-report/{report_id}")
async def resolve_report(report_id: int, _: bool = Depends(require_admin)):
    """관리자 웹 호환용: 민원을 처리 완료 상태로 변경"""
    supabase = get_supabase()
    update_data = {
        "status": "completed",
        "resolved_at": datetime.now(timezone.utc).isoformat()
    }

    result = await supabase.table("complaints").update(update_data).eq("id", report_id).execute()
    if not result.data:
        raise HTTPException(status_code=404, detail=ApiMessages.REPORT_NOT_FOUND)

    await send_status_push(report_id, "completed")
    return {"success": True, "status": "completed"}

@app.post("/stt-only")
async def stt_only(file: UploadFile = File(...)):
    """음성 전송 시 STT 텍스트 + GPT 분류 결과 반환"""
    content = await file.read()
    ext = os.path.splitext(file.filename or "")[-1].lower() or ".wav"

    # DEBUG_KEEP_AUDIO=true 이면 타임스탬프 파일명으로 보관 (오디오 품질 검사용)
    debug_keep = os.getenv("DEBUG_KEEP_AUDIO", "false").strip().lower() == "true"
    ts = datetime.now().strftime("%H%M%S")
    prefix = f"debug_{ts}" if debug_keep else f"tmp_{uuid.uuid4().hex}"
    file_path = os.path.join(UPLOAD_DIR, f"{prefix}_original{ext}")

    with open(file_path, "wb") as f:
        f.write(content)

    file_size = len(content)
    print(f"[stt-only] received: {file_path} ({file_size} bytes, debug_keep={debug_keep})")

    stt_result = await transcribe_audio(file_path)

    if not debug_keep and os.path.exists(file_path):
        os.remove(file_path)

    if not stt_result["success"]:
        raise HTTPException(status_code=500, detail=ApiMessages.STT_FAILED)

    # STT 성공 후 GPT 분류 실행 (실패해도 STT 결과는 정상 반환)
    nlp = None
    try:
        nlp_result = await classify_complaint(stt_result["text"])
        if nlp_result.get("success"):
            nlp = {
                "title": nlp_result.get("title"),
                "complaint_type": nlp_result.get("complaint_type", "field"),
                "category": nlp_result.get("category"),
                "department": nlp_result.get("department"),
                "confidence": nlp_result.get("confidence", 0.0),
            }
            print(f"[stt-only] GPT 분류 완료: type={nlp['complaint_type']}, confidence={nlp['confidence']:.2f}")
    except Exception as e:
        print(f"[stt-only] GPT 분류 실패 (STT는 정상 반환): {e}")

    return {
        "success": True,
        "stt_text": stt_result["text"],
        "nlp": nlp
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
    attachments: list[UploadFile] = File(default=[]),
    current_user: dict = Depends(get_current_user_payload),
):
    """최종 민원 제출 및 DB 저장"""
    supabase = get_supabase()
    validate_optional_lat_lng(lat, lng)
    if complaint_type == "admin_task":
        complaint_type = "admin"
    if complaint_type not in ["field", "admin"]:
        complaint_type = "field"
    if not address and lat is not None and lng is not None:
        address = reverse_geocode_address(lat, lng)

    # 1. 인증된 유저 ID 확보
    user_id = current_user["user_id"]

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

    # 3. 데이터 보완 (NLP) - 사용자가 수정한 최종 텍스트를 기반으로 다시 분류
    # 프론트엔드에서 수정한 내용이 반영되도록 항상 새로 분류하거나, 
    # 혹은 필수 필드가 비어있을 때 수행합니다.
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

        # 민원 접수 완료 → 관리자 대시보드에 실시간 알림
        await broadcast_new_complaint()

        
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


@app.get("/admin/events")
async def admin_events(_: bool = Depends(require_admin)):
    """관리자 대시보드 실시간 갱신용 SSE 엔드포인트"""
    queue: asyncio.Queue = asyncio.Queue()
    _sse_queues.append(queue)
    print(f"[sse] 관리자 연결 ({len(_sse_queues)}명 접속 중)")

    async def event_generator():
        try:
            while True:
                # 새 이벤트 대기 (연결 유지용 keep-alive 포함)
                try:
                    data = await asyncio.wait_for(queue.get(), timeout=25.0)
                    yield {"event": "new_complaint", "data": data}
                except asyncio.TimeoutError:
                    yield {"event": "ping", "data": "keep-alive"}  # 연결 유지
        except asyncio.CancelledError:
            pass
        finally:
            if queue in _sse_queues:
                _sse_queues.remove(queue)
            print(f"[sse] 관리자 연결 해제 ({len(_sse_queues)}명 접속 중)")

    return EventSourceResponse(event_generator())

@app.get("/download-attachments/{report_id}")
async def download_attachments(report_id: int, _: bool = Depends(require_admin)):
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


@app.get("/admin/stats")
async def get_stats(_: bool = Depends(require_admin)):
    """대시보드용 통계 데이터 (오늘의 추이, 부서별 비중)"""
    supabase = get_supabase()
    
    # 1. 전체 민원 (통계용)
    result = await supabase.table("complaints").select("id, department, created_at, status").execute()
    reports = result.data

    # 2. 오늘 접수된 민원 추이 (시간별)
    now = datetime.now(timezone.utc)
    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    
    hourly_counts = {i: 0 for i in range(24)}
    for r in reports:
        created_at = datetime.fromisoformat(r["created_at"].replace("Z", "+00:00"))
        if created_at >= today_start:
            hour = created_at.hour
            hourly_counts[hour] += 1
            
    today_trend = [{"hour": f"{h}시", "count": hourly_counts[h]} for h in range(24)]

    # 3. 부서별 민원 비중
    dept_counts = {}
    for r in reports:
        dept = r.get("department") or "civil"
        dept_counts[dept] = dept_counts.get(dept, 0) + 1
        
    dept_res = await supabase.table("departments").select("key, label").execute()
    dept_map = {d["key"]: d["label"] for d in dept_res.data}
    dept_map["civil"] = "민원실 (기본)"

    dept_distribution = [
        {"name": dept_map.get(k, k), "value": v} 
        for k, v in dept_counts.items()
    ]

    # 4. 상태별 요약
    status_counts = {"pending": 0, "processing": 0, "completed": 0, "rejected": 0}
    for r in reports:
        st = r.get("status", "pending")
        if st in status_counts:
            status_counts[st] += 1

    return {
        "success": True,
        "today_trend": today_trend,
        "dept_distribution": dept_distribution,
        "summary": status_counts
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
