import asyncio
import io
import zipfile
import os
from datetime import datetime
import urllib.parse

async def test_download_logic():
    nickname = "홍길동"
    attachment_urls = ["test.txt"]
    UPLOAD_DIR = "uploads"
    os.makedirs(UPLOAD_DIR, exist_ok=True)
    with open(os.path.join(UPLOAD_DIR, "test.txt"), "w") as f:
        f.write("test content")

    zip_buffer = io.BytesIO()
    date_prefix = datetime.now().strftime("%y%m%d")
    
    # Check if nickname is None
    # nickname = None # This would crash line 19
    
    safe_nickname = "".join([c for c in nickname if c.isalnum() or c in (" ", "-", "_")]).strip() or "unknown"

    files_found = 0
    with zipfile.ZipFile(zip_buffer, "w", zipfile.ZIP_DEFLATED) as zip_file:
        for file_info in attachment_urls:
            filename = os.path.basename(file_info)
            file_path = os.path.join(UPLOAD_DIR, filename)
            arc_name = f"{date_prefix}_{safe_nickname}_{filename}"
            if os.path.exists(file_path):
                zip_file.write(file_path, arcname=arc_name)
                files_found += 1
    
    print(f"Files found: {files_found}")
    zip_buffer.seek(0)
    download_name = f"{date_prefix}_{safe_nickname}_첨부파일.zip"
    encoded_name = urllib.parse.quote(download_name)
    print(f"Encoded name: {encoded_name}")
    
    # Simulate header creation
    header = f'attachment; filename="{encoded_name}"; filename*=UTF-8\'\'{encoded_name}'
    print(f"Header: {header}")

if __name__ == "__main__":
    asyncio.run(test_download_logic())
