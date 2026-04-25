# 🏛️ AI 기반 민원 행정 서비스 간소화 시스템

> STT(Whisper) + LLM(GPT-4o mini) 기반 음성 민원 접수 앱

---

## 📁 프로젝트 구조

```
2026_capstone/
├── backend-server/     # FastAPI 백엔드 서버
├── mobile-app/         # Flutter 모바일 앱 (민원인)
└── admin-web/          # React 어드민 대시보드 (관리자)
```

---

## ⚡ 빠른 시작 (git clone 후 따라하기)

### 1️⃣ 환경변수 설정

#### 📌 백엔드 서버
```bash
cd backend-server
copy .env.example .env       # Windows
# cp .env.example .env       # Mac/Linux
```
`.env` 파일을 열고 아래 값을 채우세요:
| 키 | 설명 | 발급 위치 |
|----|------|----------|
| `OPENAI_API_KEY` | Whisper + GPT-4o mini 키 | [platform.openai.com](https://platform.openai.com/api-keys) |
| `KAKAO_MAP_API_KEY` | 지도 표시용 | [developers.kakao.com](https://developers.kakao.com) |
| `SUPABASE_URL` | DB 주소 | Supabase → Settings → API |
| `SUPABASE_KEY` | DB 인증 키 | Supabase → Settings → API |

#### 📌 어드민 웹
```bash
cd admin-web
copy .env.example .env       # Windows
# cp .env.example .env       # Mac/Linux
```
`.env`에 `VITE_KAKAO_MAP_API_KEY` 값 입력

#### 📌 Flutter 앱 서버 주소
```bash
cd mobile-app/lib
copy config.dart.example config.dart    # Windows
# cp config.dart.example config.dart   # Mac/Linux
```
`config.dart` 파일을 열고 서버 주소 입력:
```dart
// AWS 배포 후
const String kServerUrl = 'http://EC2_퍼블릭IP:8000';

// ngrok 사용 시
const String kServerUrl = 'https://xxxx-xxx.ngrok-free.app';
```

---

### 2️⃣ 백엔드 서버 실행

```bash
cd backend-server

# 패키지 설치 (최초 1회)
pip install -r requirements.txt

# 서버 실행
python -m uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

서버가 정상 실행되면:
```
INFO: Uvicorn running on http://0.0.0.0:8000
INFO: Application startup complete.
```

브라우저에서 확인: `http://localhost:8000/health`

---

### 3️⃣ 어드민 웹 실행

```bash
cd admin-web

# 패키지 설치 (최초 1회)
npm install

# 개발 서버 실행
npm run dev
```

브라우저에서 확인: `http://localhost:5173`

---

### 4️⃣ Flutter 앱 실행

```bash
cd mobile-app

# 패키지 설치 (최초 1회)
flutter pub get

# 연결된 기기에서 실행
flutter run
```

---

## 🔑 주요 API 엔드포인트

| 메서드 | 경로 | 설명 |
|--------|------|------|
| `GET` | `/health` | 서버 상태 확인 |
| `POST` | `/stt-only` | 음성 → 텍스트 변환 (STT만) |
| `POST` | `/submit-complaint` | 텍스트 → NLP 분류 + DB 저장 |
| `GET` | `/complaints` | 전체 민원 목록 조회 |

---

## 🛠️ 기술 스택

| 영역 | 기술 |
|------|------|
| 모바일 앱 | Flutter (Android/iOS) |
| 어드민 웹 | React + Vite |
| 백엔드 | FastAPI + Uvicorn |
| STT | OpenAI Whisper |
| NLP | GPT-4o mini |
| 데이터베이스 | Supabase (PostgreSQL) |
| 지도 | KakaoMap API |

---

## ⚠️ 주의사항

- `.env` 파일과 `config.dart`는 **절대 git에 올리지 마세요** (자동으로 gitignore 처리됨)
- 백엔드 서버는 외부 기기(폰)에서 접속 가능하려면 `--host 0.0.0.0` 옵션 필수
- AWS 배포 시 보안그룹에서 **8000 포트 인바운드** 규칙 추가 필요
