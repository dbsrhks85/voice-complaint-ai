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

-- 2. departments 테이블 (추가)
CREATE TABLE IF NOT EXISTS departments (
    id          BIGSERIAL PRIMARY KEY,
    key         VARCHAR(50) UNIQUE NOT NULL,
    label       VARCHAR(100) NOT NULL,
    icon        VARCHAR(10),
    color       VARCHAR(20),
    keywords    TEXT[], -- 검색용 키워드
    tasks       TEXT[], -- 처리 업무 목록
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- [수정본] complaints 테이블: 워크플로우 지원을 위한 컬럼 확장
CREATE TABLE IF NOT EXISTS complaints (
    id           BIGSERIAL PRIMARY KEY,
    user_id      BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    stt_text     TEXT NOT NULL,
    title        VARCHAR(200),
    lat          DECIMAL(10,7),
    lng          DECIMAL(10,7),
    address      TEXT,                 -- [추가] 비현장 민원이나 상세 주소 정보
    category     VARCHAR(50),
    department   VARCHAR(50) REFERENCES departments(key),
    
    -- [추가] 현장(field) vs 행정(admin) 구분
    complaint_type VARCHAR(20) DEFAULT 'field' CHECK (complaint_type IN ('field', 'admin')),
    
    -- [수정] 상태값 단계 확정 (기존과 동일하지만 명시적 확인)
    status       VARCHAR(20) DEFAULT 'pending' 
                 CHECK (status IN ('pending', 'processing', 'completed', 'rejected')),
    
    audio_path      TEXT,
    attachment_urls TEXT[] DEFAULT '{}', -- [추가] 첨부 이미지/파일 URL 리스트
    attachment_note TEXT,               -- [추가] 관리자나 사용자가 남기는 추가 메모
    rejection_reason TEXT,              -- [추가] 반려 사유
    
    created_at   TIMESTAMPTZ DEFAULT NOW(),
    accepted_at  TIMESTAMPTZ,
    rejected_at  TIMESTAMPTZ,
    resolved_at  TIMESTAMPTZ
);

-- 기존 테이블을 쓰는 경우를 위한 컬럼/제약 보정
ALTER TABLE complaints ADD COLUMN IF NOT EXISTS address TEXT;
ALTER TABLE complaints ADD COLUMN IF NOT EXISTS complaint_type VARCHAR(20) DEFAULT 'field';
ALTER TABLE complaints ADD COLUMN IF NOT EXISTS attachment_urls TEXT[] DEFAULT '{}';
ALTER TABLE complaints ADD COLUMN IF NOT EXISTS attachment_note TEXT;
ALTER TABLE complaints ADD COLUMN IF NOT EXISTS rejection_reason TEXT;
ALTER TABLE complaints ADD COLUMN IF NOT EXISTS accepted_at TIMESTAMPTZ;
ALTER TABLE complaints ADD COLUMN IF NOT EXISTS rejected_at TIMESTAMPTZ;

UPDATE complaints
SET complaint_type = 'admin'
WHERE complaint_type = 'admin_task';

UPDATE complaints
SET complaint_type = 'field'
WHERE complaint_type IS NULL
   OR complaint_type NOT IN ('field', 'admin');

DO $$
DECLARE
    constraint_name TEXT;
BEGIN
    FOR constraint_name IN
        SELECT conname
        FROM pg_constraint
        WHERE conrelid = 'complaints'::regclass
          AND contype = 'c'
          AND pg_get_constraintdef(oid) LIKE '%complaint_type%'
    LOOP
        EXECUTE format('ALTER TABLE complaints DROP CONSTRAINT %I', constraint_name);
    END LOOP;

    ALTER TABLE complaints
        ADD CONSTRAINT complaints_complaint_type_check
        CHECK (complaint_type IN ('field', 'admin'));
END $$;

-- 인덱스 추가 (타입별 필터링 성능 향상)
CREATE INDEX IF NOT EXISTS idx_complaints_type   ON complaints(complaint_type);
CREATE INDEX IF NOT EXISTS idx_complaints_user   ON complaints(user_id);
CREATE INDEX IF NOT EXISTS idx_complaints_status ON complaints(status);
CREATE INDEX IF NOT EXISTS idx_complaints_gps    ON complaints(lat, lng);
CREATE INDEX IF NOT EXISTS idx_complaints_dept   ON complaints(department);
CREATE INDEX IF NOT EXISTS idx_complaints_accepted_at ON complaints(accepted_at);
CREATE INDEX IF NOT EXISTS idx_complaints_rejected_at ON complaints(rejected_at);

-- 부서 초기 데이터 삽입
INSERT INTO departments (key, label, icon, color, keywords, tasks)
VALUES
('road', '도로과', '🛣️', '#ef4444', 
 ARRAY['도로', '포트홀', '아스팔트', '차선', '보도블럭', '인도', '신호등'], 
 ARRAY['현장 위치 확인', '도로 파손 여부 점검', '긴급 보수 필요성 판단', '보수 일정 등록']),

('building', '건축과', '🏢', '#f97316', 
 ARRAY['건물', '옥상', '벽', '불법건축', '건축', '주택', '공사장'], 
 ARRAY['건축 민원 사실 확인', '관련 허가 여부 검토', '현장 점검 일정 배정', '시정명령 여부 검토']),

('park', '녹지공원과', '🌳', '#22c55e', 
 ARRAY['공원', '나무', '가로수', '잔디', '화단', '녹지'], 
 ARRAY['수목/녹지 상태 점검', '안전 위험 여부 확인', '정비 인력 배정', '정비 일정 등록']),

('traffic', '교통과', '🚦', '#3b82f6', 
 ARRAY['주차', '교통', '버스', '택시', '신호', '불법주차'], 
 ARRAY['교통 민원 유형 검토', '단속 필요 여부 판단', '현장 지도 요청', '교통 개선 검토']),

('environment', '환경과', '♻️', '#14b8a6', 
 ARRAY['쓰레기', '악취', '폐기물', '소음', '먼지', '오염'], 
 ARRAY['환경 피해 여부 조사', '현장 측정 요청', '정화/수거 조치 요청', '재발 방지 검토']),

('planning', '기획예산과', '📊', '#a855f7', 
 ARRAY['정책', '예산', '개선', '제안', '건의'], 
 ARRAY['정책 제안 검토', '예산 반영 가능성 검토', '중장기 과제 분류', '부서 협의 요청']),

('civil', '민원담당관', '🏛️', '#64748b', 
 ARRAY[]::TEXT[], 
 ARRAY['민원 내용 1차 검토', '소관 부서 재배정', '처리 기한 모니터링', '민원인 회신 관리'])
ON CONFLICT (key) DO UPDATE SET
    label = EXCLUDED.label,
    icon = EXCLUDED.icon,
    color = EXCLUDED.color,
    keywords = EXCLUDED.keywords,
    tasks = EXCLUDED.tasks;
