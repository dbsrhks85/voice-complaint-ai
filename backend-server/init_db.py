"""
Supabase에 테이블을 생성하는 초기화 스크립트.
supabase-py는 DDL(CREATE TABLE)을 직접 지원하지 않으므로
Management REST API를 통해 SQL을 실행합니다.
"""
import os
import requests
from dotenv import load_dotenv

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_KEY")

# Supabase 프로젝트 ref 추출 (URL에서 자동 파싱)
# 예: https://yfbkwuyvsrgxlbslcfck.supabase.co → yfbkwuyvsrgxlbslcfck
project_ref = SUPABASE_URL.replace("https://", "").split(".")[0]

SQL = """
CREATE TABLE IF NOT EXISTS users (
    id          BIGSERIAL PRIMARY KEY,
    kakao_id    VARCHAR(100) UNIQUE NOT NULL,
    nickname    VARCHAR(100),
    phone       VARCHAR(20),
    role        VARCHAR(10) DEFAULT 'user' CHECK (role IN ('user', 'admin')),
    push_token  TEXT,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS complaints (
    id          BIGSERIAL PRIMARY KEY,
    user_id     BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    stt_text    TEXT NOT NULL,
    title       VARCHAR(200),
    lat         DECIMAL(10,7),
    lng         DECIMAL(10,7),
    category    VARCHAR(50),
    department  VARCHAR(100),
    status      VARCHAR(20) DEFAULT 'pending'
                  CHECK (status IN ('pending', 'processing', 'completed')),
    audio_path  TEXT,
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    resolved_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_complaints_user   ON complaints(user_id);
CREATE INDEX IF NOT EXISTS idx_complaints_status ON complaints(status);
CREATE INDEX IF NOT EXISTS idx_complaints_gps    ON complaints(lat, lng);
"""

def run():
    url = f"https://api.supabase.com/v1/projects/{project_ref}/database/query"
    headers = {
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json"
    }
    resp = requests.post(url, headers=headers, json={"query": SQL})

    if resp.status_code == 200:
        print("✅ 테이블 생성 성공!")
        print(resp.json())
    else:
        print(f"❌ 실패 (status {resp.status_code})")
        print(resp.text)
        print()
        print("─" * 50)
        print("💡 아래 SQL을 Supabase Dashboard > SQL Editor에 직접 붙여넣고 실행하세요:")
        print("   https://supabase.com/dashboard/project/" + project_ref + "/sql/new")
        print("─" * 50)
        print(SQL)

if __name__ == "__main__":
    run()
