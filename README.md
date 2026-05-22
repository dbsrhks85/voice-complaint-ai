<div align="center">

<img src="mobile-app/assets/images/app_logo.png" alt="민원이 앱 로고" width="120"/>

# 스마트 민원 24
### AI 기반 음성 민원 접수 서비스

> **"말 한마디로 끝내는 민원"**  
> 스마트폰 마이크에 대고 불편함을 말하면,  
> AI가 자동으로 분류 · 접수 · 담당부서 배정까지 처리합니다.

<br>

![Flutter](https://img.shields.io/badge/Flutter-3.11-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![FastAPI](https://img.shields.io/badge/FastAPI-0.135-009688?style=for-the-badge&logo=fastapi&logoColor=white)
![React](https://img.shields.io/badge/React-18-61DAFB?style=for-the-badge&logo=react&logoColor=black)
![OpenAI](https://img.shields.io/badge/OpenAI-Whisper%20+%20GPT--4o_mini-412991?style=for-the-badge&logo=openai&logoColor=white)
![Supabase](https://img.shields.io/badge/Supabase-PostgreSQL-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white)
![Firebase](https://img.shields.io/badge/Firebase-FCM-FFCA28?style=for-the-badge&logo=firebase&logoColor=black)

</div>

<br>

---

##  프로젝트 개요

<img src="mobile-app/assets/images/minwoni.png" alt="민원이 마스코트" align="right" width="180"/>

**민원이**는 공공 행정 서비스의 디지털 접근성을 높이기 위해 개발된 **AI 기반 음성 민원 자동 접수 시스템**입니다.

###  문제 인식

기존 민원 접수 방식은 **시민에게 불필요한 부담**을 줍니다.

-  **전화**: 대기 시간이 길고 담당 부서를 몰라 여러 곳에 연결
-  **온라인 양식**: 복잡한 분류 체계, 어느 부서에 넣어야 할지 모름
-  **방문 접수**: 시간과 이동 비용 소요

### 우리의 해결책

> 말로 하면 AI가 알아서 처리해준다

1. **음성으로 접수** — 녹음 버튼 하나로 불편한 상황을 말하기만 하면 됨
2. **AI가 자동 분류** — Whisper STT + GPT-4o mini가 카테고리·부서·제목 자동 생성
3. **실시간 처리 알림** — 민원이 수락·처리완료·반려될 때 즉시 푸시 알림

<br>

| 구분 | 내용 |
|------|------|
| **프로젝트 유형** | 캡스톤 디자인 / 경진대회 출품작 |
| **개발 기간** | 2026년 3월~5월 |
| **서비스 대상** | 시민 (모바일 앱) + 담당 공무원 (웹 대시보드) |
| **플랫폼** | Android / iOS 앱 + 웹 관리자 대시보드 |
| **최종 배포 브랜치** | `main2` |

<br>

---

##  핵심 기능

###  시민용 모바일 앱 (Flutter)

| 기능 | 설명 |
|------|------|
|  **음성 민원 접수** | 녹음 버튼 하나로 민원 내용을 말하면 자동으로 텍스트 변환 |
|  **AI 자동 분류** | GPT-4o mini가 카테고리 · 담당부서 · 제목을 자동 생성 |
|  **내용 직접 수정** | STT 결과를 사용자가 직접 검토·수정한 뒤 최종 접수 |
|  **위치 첨부** | GPS 자동 감지 + 카카오 지도로 민원 위치 직접 선택 |
|  **파일 첨부** | 현장 사진·파일 첨부 지원 |
|  **실시간 푸시 알림** | 민원 수락 · 처리완료 · 반려 시 FCM 즉시 알림 |
|  **내 민원 조회** | 접수한 민원 목록 및 처리 상태 실시간 추적 |
|  **카카오 로그인** | 카카오 소셜 로그인으로 간편 인증 (OAuth 2.0) |

### 🖥️관리자 웹 대시보드 (React + Vite)

| 기능 | 설명 |
|------|------|
| **민원 통합 현황** | 전체 민원을 상태별(대기 · 처리중 · 완료 · 반려)로 한눈에 확인 |
| **카카오 지도 연동** | 현장 민원 위치를 지도 마커로 시각화 → 클릭 시 민원 상세 자동 연동 |
| **긴급도 자동 표시** | 접수일 경과일(3일 이하 🟢 / 7일 이하 🟡 / 7일 초과 🔴)에 따른 색상 구분 |
| **다중 필터** | 부서 · 유형(현장/행정) · 상태 · 키워드 복합 필터링 |
| **상태 워크플로우** | 수락 → 처리중 → 완료 / 반려(사유 입력) 단계별 처리 |
| **통계 분석** | 기간별 접수 추이 (AreaChart) + 부서별 처리 현황 (PieChart) |
| **부서 동적 관리** | 담당 부서 추가 · 삭제 · 민원 일괄 재배정 |
| **첨부파일 다운로드** | 민원별 첨부파일 ZIP 일괄 다운로드 |
| **관리자 전용 로그인** | 발급된 계정으로만 접근 (JWT Bearer 인증) |

<br>

---

##  AI 처리 파이프라인

```
사용자 음성 입력 (Flutter 앱 내 녹음)
         │
         ▼
  ┌─────────────────┐
  │  FFmpeg 전처리   │  노이즈 정규화, 16kHz 모노 변환 (Whisper 최적화)
  └────────┬────────┘
           │
           ▼
  ┌─────────────────────────────┐
  │  OpenAI Whisper (whisper-1) │  한국어 특화 프롬프트 적용
  │  한국어 STT 변환             │  의심스러운 결과 감지 시 원본 오디오 재시도
  └────────┬────────────────────┘
           │ 텍스트
           ▼
  ┌─────────────────────────────┐
  │  GPT-4o mini (NLP 분류)      │  DB 부서 목록 기반 동적 시스템 프롬프트 생성
  │  temperature=0.0             │  JSON 형식 강제 응답
  └────────┬────────────────────┘
           │
           ▼  JSON 응답
           ├── title          (민원 제목, 20자 이내)
           ├── category       (repair / suggestion / inquiry / permission)
           ├── department     (road / building / park / traffic / environment / planning / civil)
           ├── complaint_type (field 현장 / admin 행정)
           └── confidence     (분류 신뢰도 0.0 ~ 1.0)
           │
           ▼
  ┌──────────────────────────────────────────┐
  │  Supabase DB 저장 + SSE 브로드캐스트      │  관리자 대시보드 실시간 갱신
  └──────────────────────────────────────────┘
```

<br>

---

## 🛠️ 기술 스택

### Frontend — 모바일 앱

| 기술 | 버전 | 용도 |
|------|------|------|
| **Flutter** | SDK ^3.11 | 크로스플랫폼 모바일 앱 (Android / iOS) |
| **Dio** | ^5.9 | REST API HTTP 통신 |
| **Geolocator** | ^14.0 | GPS 위치 정보 획득 |
| **Record** | ^6.2 | 디바이스 마이크 음성 녹음 |
| **KakaoMap Plugin** | ^0.4 | 지도 표시 및 위치 핀 선택 |
| **Kakao Flutter SDK** | ^2.0 | 카카오 소셜 로그인 (OAuth 2.0) |
| **Firebase Messaging** | ^16.2 | FCM 푸시 알림 수신 |
| **Flutter Secure Storage** | ^9.2 | JWT 토큰 안전 저장 |
| **Image Picker / File Picker** | - | 사진·파일 첨부 |

### Frontend — 관리자 웹

| 기술 | 버전 | 용도 |
|------|------|------|
| **React** | ^18 | UI 컴포넌트 프레임워크 |
| **Vite** | ^5 | 빌드 도구 및 개발 서버 |
| **Recharts** | - | 통계 시각화 (AreaChart, PieChart) |
| **KakaoMap API** | - | 민원 위치 지도 표시 및 마커 |
| **fetch-event-source** | - | SSE 실시간 스트리밍 수신 |

### Backend

| 기술 | 버전 | 용도 |
|------|------|------|
| **FastAPI** | 0.135 | 비동기 REST API 서버 |
| **Uvicorn** | 0.41 | ASGI 서버 |
| **OpenAI Whisper** (`whisper-1`) | - | 음성 → 텍스트 변환 (STT) |
| **GPT-4o mini** | - | 민원 자동 분류 · 제목 생성 (NLP) |
| **Supabase** (PostgreSQL) | 2.28 | 클라우드 관계형 데이터베이스 |
| **Firebase Admin SDK** | - | FCM 푸시 알림 서버 발송 |
| **Kakao Local API** | - | 좌표 → 도로명 주소 역지오코딩 |
| **python-jose** | - | JWT 인증 토큰 발급·검증 |
| **FFmpeg** | - | 업로드 오디오 정규화 전처리 |

<br>

---

## 시스템 아키텍처

```
┌──────────────────────────────────────────────────────────────┐
│                     시민 (Flutter App)                        │
│   카카오 로그인 → 음성 녹음 → STT → AI 분류 확인 → 민원 접수    │
└──────────────────────────┬───────────────────────────────────┘
                           │ HTTPS
                           ▼
┌──────────────────────────────────────────────────────────────┐
│                FastAPI 백엔드 서버 (AWS EC2)                   │
│                                                              │
│   /auth/*              카카오 OAuth + JWT 토큰 발급/갱신       │
│   /stt-only            FFmpeg → Whisper STT + GPT 분류       │
│   /submit-complaint    민원 접수 + 첨부파일 저장 + DB Insert   │
│   /get-reports         전체 민원 조회 (관리자 전용)            │
│   /update-status/{id}  상태 변경 + FCM 푸시 발송              │
│   /admin/events        SSE 실시간 이벤트 스트림                │
│   /admin/stats         통계 집계 API                         │
│   /admin/*             부서 추가/삭제, 관리자 인증             │
└──────┬──────────────────────────────┬────────────────────────┘
       │                              │
       ▼                              ▼
┌─────────────┐           ┌───────────────────────┐
│  Supabase   │           │     OpenAI API         │
│ PostgreSQL  │           │  whisper-1 + gpt-4o    │
│             │           │  mini                  │
│ users       │           └───────────────────────┘
│ complaints  │
│ departments │           ┌───────────────────────┐
│ admin_users │           │    Firebase FCM        │
└─────────────┘           │    푸시 알림 발송       │
                          └────────────┬──────────┘
                                       │ 푸시 알림
                                       ▼
┌───────────────────────────┐    ┌─────────────────────┐
│  관리자 웹 (React + Vite)  │    │  시민 Flutter App    │
│  카카오 지도 + 통계 차트    │    │  (알림 수신)         │
│                           │    └─────────────────────┘
│  ←── SSE 실시간 갱신 ──────┘
└───────────────────────────┘
```

<br>

---

##  데이터베이스 스키마

```sql
-- 시민 계정
users (
  id, kakao_id UNIQUE, nickname, role,
  push_token,   -- FCM 디바이스 토큰
  created_at
)

-- 민원 데이터 (핵심 테이블)
complaints (
  id, user_id,
  stt_text,              -- Whisper 변환 원문
  title,                 -- GPT 생성 제목 (20자)
  lat, lng, address,     -- 위치 정보
  category,              -- repair / suggestion / inquiry / permission
  department,            -- 담당 부서 key (FK → departments)
  complaint_type,        -- field(현장) / admin(행정)
  status,                -- pending → processing → completed / rejected
  attachment_urls[],     -- 첨부파일 경로 목록
  attachment_note,       -- 추가 메모
  rejection_reason,      -- 반려 사유
  created_at, accepted_at, rejected_at, resolved_at
)

-- 담당 부서 (관리자가 동적으로 관리)
departments (
  id, key UNIQUE, label, color, phone,
  keywords[],   -- AI 분류에 사용되는 키워드
  tasks[]       -- 부서 처리 업무 목록
)

-- 관리자 계정
admin_users (id, username, password_hash, name, role, is_active, last_login_at)

-- 사용자 리프레시 토큰
auth_refresh_tokens (id, user_id, token_hash, expires_at, revoked_at)
```

**인덱스**: `complaints(user_id)`, `(status)`, `(lat, lng)`, `(department)`, `(complaint_type)`, `(accepted_at)`, `(rejected_at)`

<br>

---

##  민원 처리 워크플로우

```
시민 음성 접수
      │
      ▼
  [pending] 접수 대기
      │
      ├── 관리자 수락 ──▶ [processing] 처리중
      │                        │
      │                        └──▶ [completed] 처리완료  FCM 알림
      │
      └── 관리자 반려 ──▶ [rejected] 반려됨 (사유 기록)  FCM 알림
```

- **긴급도 자동 판별**: 접수 후 3일 이내 🟢 / 7일 이내 🟡 / 7일 초과 🔴
- **자동 정리**: 처리 완료 민원은 **완료 후 10일이 지나면** 대시보드에서 자동 숨김
- **실시간 알림**: 새 민원 접수 시 관리자 웹에 **SSE로 즉시 브로드캐스트**

<br>

---

## 📁 프로젝트 구조

```
2026_capstone/                    (배포 브랜치: main2)
│
├── backend-server/               # FastAPI 백엔드
│   ├── main.py                   # 전체 API 엔드포인트 (872줄)
│   ├── stt_engine.py             # Whisper STT + FFmpeg 전처리
│   ├── nlp_engine.py             # GPT-4o mini 민원 분류 엔진
│   ├── database.py               # Supabase 비동기 클라이언트
│   ├── messages.py               # API 응답 메시지 상수
│   ├── routers/
│   │   ├── auth.py               # 카카오 OAuth + JWT 발급
│   │   ├── admin_auth.py         # 관리자 로그인/로그아웃
│   │   └── me.py                 # 내 정보 조회
│   ├── core/
│   │   ├── security.py           # JWT 토큰 검증 미들웨어
│   │   └── admin_auth.py         # 관리자 권한 체크 의존성
│   ├── create_tables.sql         # DB 스키마 + 초기 부서 데이터
│   └── requirements.txt
│
├── mobile-app/                   # Flutter 모바일 앱
│   └── lib/
│       ├── main.dart             # 앱 전체 (화면·상태관리, 101KB)
│       ├── map_picker_page.dart  # 카카오 지도 위치 직접 선택
│       ├── onboarding_screen.dart
│       ├── config.dart           # 서버 URL 설정 (gitignore)
│       ├── services/             # API 통신 레이어
│       └── widgets/              # 재사용 가능 위젯
│
└── admin-web/                    # React 관리자 대시보드
    └── src/
        ├── App.jsx               # 전체 대시보드 (1503줄)
        └── index.css             # 전역 스타일 (43KB)
```

<br>

---

##  주요 API 엔드포인트

| 메서드 | 경로 | 인증 | 설명 |
|--------|------|:----:|------|
| `GET` | `/health` | — | 서버 및 DB 상태 확인 |
| `POST` | `/auth/kakao/login` | — | 카카오 로그인 + JWT 발급 |
| `POST` | `/stt-only` |  사용자 | 음성 파일 → STT + AI 분류 결과 반환 |
| `POST` | `/submit-complaint` |  사용자 | 민원 최종 접수 (텍스트 + 위치 + 첨부파일) |
| `GET` | `/get-reports/{kakao_id}` |  사용자 | 내 민원 목록 조회 |
| `POST` | `/register-push-token` |  사용자 | FCM 디바이스 토큰 등록 |
| `GET` | `/get-departments` | — | 담당 부서 목록 조회 |
| `GET` | `/reverse-geocode` | — | 위도/경도 → 도로명 주소 변환 |
| `GET` | `/get-reports` |  관리자 | 전체 민원 목록 조회 |
| `POST` | `/update-status/{id}` |  관리자 | 민원 상태 변경 + FCM 알림 발송 |
| `POST` | `/resolve-report/{id}` |  관리자 | 민원 처리 완료 처리 |
| `GET` | `/admin/events` |  관리자 | SSE 실시간 이벤트 스트림 |
| `GET` | `/admin/stats` |  관리자 | 통계 데이터 조회 |
| `POST` | `/admin/add-department` |  관리자 | 담당 부서 추가 |
| `DELETE` | `/admin/delete-department/{id}` |  관리자 | 부서 삭제 + 민원 재배정 |
| `GET` | `/download-attachments/{id}` |  관리자 | 첨부파일 ZIP 일괄 다운로드 |
| `POST` | `/admin/auth/login` | — | 관리자 로그인 |

<br>

---

##  로컬 실행 가이드

### 사전 준비 — 필요한 외부 API 키

| 환경 변수 | 용도 | 발급 위치 |
|-----------|------|-----------|
| `OPENAI_API_KEY` | Whisper STT + GPT-4o mini | [platform.openai.com](https://platform.openai.com/api-keys) |
| `SUPABASE_URL` | DB 엔드포인트 | [supabase.com](https://supabase.com) → Settings → API |
| `SUPABASE_KEY` | DB 서비스 키 | 위 동일 |
| `KAKAO_REST_API_KEY` | 좌표→주소 역지오코딩 | [developers.kakao.com](https://developers.kakao.com) |
| `KAKAO_MAP_API_KEY` | 지도 표시 (관리자 웹) | 위 동일 |
| `FIREBASE_CREDENTIALS_PATH` | FCM 서버 발송 | Firebase Console → 프로젝트 설정 → 서비스 계정 |

---

### 1️⃣ 백엔드 서버

```bash
cd backend-server

# 환경 변수 설정
copy .env.example .env        # Windows
# cp .env.example .env        # Mac / Linux
# → .env 파일에 위 API 키 값 입력

# 패키지 설치
pip install -r requirements.txt

# DB 초기화 (Supabase SQL Editor에서 실행)
# create_tables.sql 내용 붙여넣기 → Run

# 서버 실행
python -m uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

 정상 실행 확인: `http://localhost:8000/health`  
 Swagger API 문서: `http://localhost:8000/docs`

---

### 2️⃣ 관리자 웹

```bash
cd admin-web

copy .env.example .env        # VITE_KAKAO_MAP_API_KEY 입력

npm install
npm run dev
```

 브라우저에서 확인: `http://localhost:5173`

---

### 3️⃣ Flutter 모바일 앱

```bash
cd mobile-app/lib

# 서버 주소 설정
copy config.dart.example config.dart
# config.dart의 kServerUrl을 실제 서버 주소로 변경

cd ..
flutter pub get
flutter run
```

> **외부 기기(실제 폰)에서 테스트 시**: 백엔드 서버를 `--host 0.0.0.0`으로 실행하고, `config.dart`에 PC의 로컬 IP를 입력하세요.

<br>

---

##  AWS 배포 구성

```
AWS EC2 인스턴스
  └── FastAPI + Uvicorn
      ├── 보안 그룹 인바운드: TCP 8000 허용
      └── 환경 변수: .env 파일로 관리

Flutter 앱   → config.dart의 kServerUrl을 EC2 퍼블릭 IP로 설정
관리자 웹    → Vercel / Netlify 또는 EC2 nginx로 서빙
Supabase DB  → 클라우드 PostgreSQL (별도 서버 불필요)
Firebase     → 클라우드 FCM (별도 서버 불필요)
```

<br>

---

##  보안 주의사항

- `.env`, `config.dart`, `firebase-service-account.json`은 **절대 git에 커밋하지 마세요** (모두 `.gitignore` 처리됨)
- 관리자 계정 생성은 **서버 API 또는 DB 직접 삽입**으로만 가능 (공개 회원가입 없음)
- 모든 관리자 API는 **JWT Bearer 토큰** 인증 필수
- 사용자 API는 **카카오 OAuth 기반 JWT** 인증

<br>

---

##  팀원 및 역할

| 역할 | 주요 담당 |
|------|-----------|
| **Flutter 앱 개발** | 모바일 앱 전체 UI/UX, 음성 녹음, 카카오 지도·로그인 연동, FCM 수신 |
| **FastAPI 백엔드** | STT/NLP AI 파이프라인, REST API 설계, DB 스키마, 인증 시스템 |
| **React 관리자 웹** | 대시보드 UI, 카카오 지도 마커 연동, Recharts 통계 시각화 |

<br>

---

##  라이선스

본 프로젝트는 학술 및 비상업적 목적으로 개발되었습니다.

---

<div align="center">

<img src="mobile-app/assets/images/minwoni.png" alt="민원이 마스코트" width="100"/>

*"민원이와 함께라면 민원도 쉽게!"*

**2026 캡스톤 디자인**

</div>
