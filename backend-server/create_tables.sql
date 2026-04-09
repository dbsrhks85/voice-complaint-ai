-- =============================================
-- AI 민원 서비스 - Supabase 테이블 생성 SQL
-- Supabase Dashboard > SQL Editor 에 붙여넣고 Run
-- =============================================

-- 1. users 테이블
CREATE TABLE IF NOT EXISTS users (
    id          BIGSERIAL PRIMARY KEY,
    kakao_id    VARCHAR(100) UNIQUE NOT NULL,
    nickname    VARCHAR(100),
    phone       VARCHAR(20),
    role        VARCHAR(10) DEFAULT 'user' CHECK (role IN ('user', 'admin')),
    push_token  TEXT,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- 2. complaints 테이블
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

-- 인덱스
CREATE INDEX IF NOT EXISTS idx_complaints_user   ON complaints(user_id);
CREATE INDEX IF NOT EXISTS idx_complaints_status ON complaints(status);
CREATE INDEX IF NOT EXISTS idx_complaints_gps    ON complaints(lat, lng);
