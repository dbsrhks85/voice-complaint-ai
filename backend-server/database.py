import os
from supabase import create_client, Client
from dotenv import load_dotenv

# UTF-8 명시 로드
load_dotenv(encoding="utf-8")

SUPABASE_URL: str = os.getenv("SUPABASE_URL", "")
SUPABASE_KEY: str = os.getenv("SUPABASE_KEY", "")

if not SUPABASE_URL or not SUPABASE_KEY:
    raise ValueError("SUPABASE_URL or SUPABASE_KEY is not set in .env")

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)
