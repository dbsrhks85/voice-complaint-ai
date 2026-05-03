import io
import zipfile
import urllib.parse
from datetime import datetime

def test_safe_nickname(nickname):
    try:
        date_prefix = datetime.now().strftime("%y%m%d")
        nickname_str = str(nickname)
        safe_nickname = "".join([c for c in nickname_str if c.isalnum() or c in (" ", "-", "_")]).strip() or "unknown"
        print(f"Nickname: {nickname} ({type(nickname)}) -> Safe Nickname: {safe_nickname}")
    except Exception as e:
        print(f"FAILED for {nickname}: {e}")

if __name__ == "__main__":
    test_safe_nickname("홍길동")
    test_safe_nickname(None)
    test_safe_nickname(12345)
    test_safe_nickname("")
