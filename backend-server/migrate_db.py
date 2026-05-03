import os
import requests
from dotenv import load_dotenv

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_KEY")

project_ref = SUPABASE_URL.replace("https://", "").split(".")[0]

SQL = """
-- 1. 반려 사유 컬럼 추가
ALTER TABLE complaints ADD COLUMN IF NOT EXISTS rejection_reason TEXT;
ALTER TABLE complaints ADD COLUMN IF NOT EXISTS accepted_at TIMESTAMPTZ;
ALTER TABLE complaints ADD COLUMN IF NOT EXISTS rejected_at TIMESTAMPTZ;

-- 2. 상태 제약 조건 업데이트 (rejected 추가)
DO $$
DECLARE
    constraint_name TEXT;
BEGIN
    FOR constraint_name IN
        SELECT conname
        FROM pg_constraint
        WHERE conrelid = 'complaints'::regclass
          AND contype = 'c'
          AND pg_get_constraintdef(oid) LIKE '%status%'
    LOOP
        EXECUTE format('ALTER TABLE complaints DROP CONSTRAINT %I', constraint_name);
    END LOOP;

    ALTER TABLE complaints
        ADD CONSTRAINT complaints_status_check
        CHECK (status IN ('pending', 'processing', 'completed', 'rejected'));
END $$;

CREATE INDEX IF NOT EXISTS idx_complaints_accepted_at ON complaints(accepted_at);
CREATE INDEX IF NOT EXISTS idx_complaints_rejected_at ON complaints(rejected_at);
"""

def run():
    # Management API endpoint (Note: This usually requires a Management API Token, not anon key)
    # But we follow the pattern in init_db.py
    url = f"https://api.supabase.com/v1/projects/{project_ref}/database/query"
    headers = {
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json"
    }
    print(f"Running migration on project: {project_ref}...")
    try:
        resp = requests.post(url, headers=headers, json={"query": SQL}, timeout=10)
        if resp.status_code == 200:
            print("Migration Success: Column added and constraints updated!")
        else:
            print(f"Migration Failed via API (Status {resp.status_code}).")
            print("Response:", resp.text)
            print("\n" + "="*50)
            print("Please run the following SQL in Supabase SQL Editor manually:")
            print("="*50)
            print(SQL)
            print("="*50)
    except Exception as e:
        print(f"Error connecting to Supabase API: {e}")
        print("\nPlease run the SQL manually in Supabase Dashboard.")

if __name__ == "__main__":
    run()
