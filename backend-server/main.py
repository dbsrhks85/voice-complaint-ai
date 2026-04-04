# python -m uvicorn main:app --reload 로 서버를 항시 켜둘 수 있음(터미널에서 명령어 입력)
import os
import json
import shutil
from fastapi import FastAPI, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from datetime import datetime, timedelta
from dotenv import load_dotenv

from stt_engine import transcribe_audio
from nlp_engine import classify_complaint

# .env 파일에서 환경변수 로드
load_dotenv()

app = FastAPI(
    title="AI 민원 접수 시스템",
    description="음성 기반 민원 자동 접수 및 분류 API",
    version="1.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# 업로드 디렉토리 경로
UPLOAD_DIR = os.path.join(os.path.dirname(__file__), "uploads")
os.makedirs(UPLOAD_DIR, exist_ok=True)

# ✅ STT 결과 JSON 저장 폴더 (PC에서 바로 확인 가능)
STT_RESULTS_DIR = os.path.join(os.path.dirname(__file__), "..", "mobile-app", "stt_test_results")
os.makedirs(STT_RESULTS_DIR, exist_ok=True)

# 자동 증가 ID 카운터
next_id = 3

# 데이터베이스 대용 임시 리스트
reports = [
    {
        "id": 1,
        "title": "중앙로 15번길 가로등 점등 불량",
        "lat": 37.8820,
        "lng": 127.7305,
        "category": "repair",
        "department": "시설관리과",
        "stt_text": "(더미 데이터)",
        "confidence": 1.0,
        "status": "pending",
        "created_at": "2026-03-10 10:00:00",
        "resolved_at": None
    },
    {
        "id": 2,
        "title": "효자동 쓰레기 무단투기 단속 건의",
        "lat": 37.8750,
        "lng": 127.7450,
        "category": "suggestion",
        "department": "민원봉사과",
        "stt_text": "(더미 데이터)",
        "confidence": 1.0,
        "status": "pending",
        "created_at": "2026-03-10 12:00:00",
        "resolved_at": None
    }
]


# ===== 기존 API =====

@app.get("/get-reports")
def get_reports():
    """민원 목록 조회 (10일 자동 삭제 포함)"""
    now = datetime.now()
    active_reports = []
    for r in reports:
        # [기능] 10일 자동 삭제 로직
        if r["status"] == "completed" and r["resolved_at"]:
            resolved_time = datetime.strptime(r["resolved_at"], "%Y-%m-%d %H:%M:%S")
            if now - resolved_time > timedelta(days=10):
                continue
        active_reports.append(r)
    return active_reports


@app.post("/resolve-report/{report_id}")
def resolve_report(report_id: int):
    """민원 처리 완료"""
    for r in reports:
        if r["id"] == report_id:
            r["status"] = "completed"
            r["resolved_at"] = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            return {"status": "success"}
    return {"status": "error", "message": "해당 ID의 민원을 찾을 수 없습니다."}


# ===== 새로운 AI 파이프라인 API =====

@app.post("/upload-audio")
async def upload_audio(
    file: UploadFile = File(..., description="음성 파일 (m4a, wav, mp3 등)"),
    lat: float = Form(..., description="위도 (GPS)"),
    lng: float = Form(..., description="경도 (GPS)")
):
    """
    🎙️ 음성 민원 접수 API
    
    1. 음성 파일을 서버에 저장
    2. Whisper STT로 텍스트 변환
    3. GPT-4o mini로 민원 분류
    4. 민원 데이터 생성 및 저장
    """
    global next_id

    # 1단계: 음성 파일 저장
    timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    file_name = f"report_{timestamp}_{file.filename}"
    file_path = os.path.join(UPLOAD_DIR, file_name)

    with open(file_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)

    # 2단계: STT (음성 → 텍스트)
    stt_result = await transcribe_audio(file_path)

    # ✅ STT 결과 JSON 저장 (성공/실패 모두) → uploads 폴더에 저장
    label = "normalized" if file.filename and "normalized" in file.filename else "original"
    stt_json_path = os.path.join(UPLOAD_DIR, f"stt_result_{label}_{timestamp}.json")
    stt_payload = {
        "label": label,
        "file": file.filename,
        "timestamp": datetime.now().isoformat(),
        "success": stt_result["success"],
        "stt_text": stt_result.get("text", ""),
        "category": None,
        "department": None,
        "confidence": None,
        "error": stt_result.get("error")
    }
    with open(stt_json_path, "w", encoding="utf-8") as f:
        json.dump(stt_payload, f, ensure_ascii=False, indent=2)
    print(f"[STT-JSON] 저장 완료: {stt_json_path}")

    if not stt_result["success"]:
        return {
            "success": False,
            "step": "stt",
            "error": stt_result["error"],
            "message": "음성 인식에 실패했습니다. 다시 시도해주세요."
        }

    stt_text = stt_result["text"]

    # 3단계: NLP 분류 (텍스트 → 카테고리/부서)
    nlp_result = await classify_complaint(stt_text)

    if not nlp_result["success"]:
        return {
            "success": False,
            "step": "nlp",
            "stt_text": stt_text,
            "error": nlp_result["error"],
            "message": "민원 분류에 실패했습니다. 텍스트는 정상 변환되었습니다."
        }

    # 4단계: 민원 데이터 생성
    new_report = {
        "id": next_id,
        "title": nlp_result["title"],
        "lat": lat,
        "lng": lng,
        "category": nlp_result["category"],
        "department": nlp_result["department"],
        "stt_text": stt_text,
        "confidence": nlp_result["confidence"],
        "status": "pending",
        "created_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "resolved_at": None
    }

    reports.append(new_report)
    next_id += 1

    # ✅ STT 결과를 PC의 mobile-app/stt_test_results/ 에 JSON으로 저장
    timestamp_str = datetime.now().strftime("%Y%m%d_%H%M%S")
    label = "normalized" if file.filename and "normalized" in file.filename else "original"
    stt_json_path = os.path.join(
        STT_RESULTS_DIR,
        f"stt_result_{label}_{timestamp_str}.json"
    )
    stt_payload = {
        "label": label,
        "file": file.filename,
        "timestamp": datetime.now().isoformat(),
        "success": True,
        "stt_text": stt_text,
        "category": nlp_result["category"],
        "department": nlp_result["department"],
        "confidence": nlp_result["confidence"],
        "error": None
    }
    with open(stt_json_path, "w", encoding="utf-8") as f:
        json.dump(stt_payload, f, ensure_ascii=False, indent=2)
    print(f"[STT-JSON] 저장 완료: {stt_json_path}")

    return {
        "success": True,
        "message": "민원이 성공적으로 접수되었습니다.",
        "report": new_report,
        "stt_text": stt_text
    }


@app.get("/health")
def health_check():
    """서버 상태 확인"""
    api_key_set = bool(os.getenv("OPENAI_API_KEY") and os.getenv("OPENAI_API_KEY") != "여기에_OpenAI_API_키_입력")
    return {
        "status": "running",
        "api_key_configured": api_key_set,
        "total_reports": len(reports),
        "server_time": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    }