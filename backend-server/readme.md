# Backend Server — AI 민원 시스템 (FastAPI)

여기는 AI서버 및 DB연동 폴더임 (FastAPI / Supabase)

---

## 🚀 시작하는 법

### 1. 패키지 설치 (최초 1회)
```bash
pip install -r requirements.txt
```
> ⚠️ `requirements.txt`가 업데이트되면 팀원 모두 다시 실행해야 합니다.

### 2. 서버 실행
```bash
python -m uvicorn main:app --reload
```

### 3. API 문서 확인
서버 실행 후 브라우저에서 접속:
- Swagger UI: http://127.0.0.1:8000/docs
- 헬스체크: http://127.0.0.1:8000/health

---

## 📦 패키지 목록 (requirements.txt)

| 패키지 | 버전 | 용도 |
|--------|------|------|
| fastapi | 0.135.1 | 웹 프레임워크 |
| uvicorn | 0.41.0 | ASGI 서버 |
| python-multipart | 0.0.22 | 파일 업로드 처리 |
| openai | 2.26.0 | Whisper STT + GPT-4o mini |
| python-dotenv | 1.2.2 | .env 환경변수 로드 |
| supabase | 2.28.3 | DB 연동 |

---

## 📁 파일 구조

```
backend-server/
├── main.py          # API 엔드포인트 (FastAPI 앱)
├── stt_engine.py    # 음성 → 텍스트 (Whisper)
├── nlp_engine.py    # 텍스트 → 카테고리 분류 (GPT-4o mini)
├── database.py      # Supabase 클라이언트 초기화
├── messages.py      # 서버 메시지 상수 모음
├── requirements.txt # 패키지 의존성
├── create_tables.sql # DB 테이블 생성 SQL
└── uploads/         # 업로드된 음성 파일 저장 폴더
```

---

## ⚙️ 환경변수 설정

`backend-server/.env` 파일을 생성하고 아래 값을 채워주세요:
```
OPENAI_API_KEY=sk-...
SUPABASE_URL=https://xxxx.supabase.co
SUPABASE_KEY=eyJ...
KAKAO_REST_API_KEY=카카오_REST_API_키
```
> `.env` 파일은 git에 올리지 않습니다 (`.gitignore` 처리됨)
