#!/bin/bash
# ============================================================
# AI 민원 시스템 - 백엔드 서버 초기 셋업 스크립트
# AWS EC2 (Ubuntu 22.04 기준) 최초 1회 실행
# 사용법: bash setup.sh
# ============================================================

set -e  # 오류 발생 시 즉시 중단

echo "🚀 AI 민원 서버 초기 셋업을 시작합니다..."

# ── 1. 시스템 패키지 업데이트 ───────────────────────────────
echo ""
echo "📦 [1/4] 시스템 패키지 업데이트 중..."
sudo apt update -y && sudo apt upgrade -y

# ── 2. ffmpeg 설치 (서버 오디오 정규화에 필수) ─────────────
echo ""
echo "🎙️  [2/4] ffmpeg 설치 중..."
sudo apt install -y ffmpeg
ffmpeg -version | head -1
echo "✅ ffmpeg 설치 완료"

# ── 3. Python 가상환경 생성 및 패키지 설치 ─────────────────
echo ""
echo "🐍 [3/4] Python 가상환경 및 패키지 설치 중..."
sudo apt install -y python3-venv python3-pip

if [ ! -d "venv" ]; then
    python3 -m venv venv
    echo "✅ 가상환경 생성 완료"
else
    echo "ℹ️  가상환경이 이미 존재합니다. 스킵."
fi

source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
echo "✅ Python 패키지 설치 완료"

# ── 4. 필수 파일 존재 여부 확인 ────────────────────────────
echo ""
echo "🔍 [4/4] 필수 파일 확인 중..."

MISSING=0
if [ ! -f ".env" ]; then
    echo "❌ .env 파일이 없습니다! 개발자에게 요청하세요."
    MISSING=1
else
    echo "✅ .env 파일 확인"
fi

if [ ! -f "firebase-service-account.json" ]; then
    echo "⚠️  firebase-service-account.json 없음 (푸시 알림 비활성화됨)"
else
    echo "✅ firebase-service-account.json 확인"
fi

if [ $MISSING -eq 1 ]; then
    echo ""
    echo "❗ 누락된 파일이 있습니다. 위 항목을 확인하고 다시 실행하세요."
    exit 1
fi

# ── 완료 ─────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "✅ 셋업 완료!"
echo ""
echo "▶  서버 실행 명령어:"
echo "   source venv/bin/activate"
echo "   python -m uvicorn main:app --host 0.0.0.0 --port 8000"
echo "============================================================"
