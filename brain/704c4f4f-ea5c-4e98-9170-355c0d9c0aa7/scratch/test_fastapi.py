from fastapi import FastAPI
from fastapi.responses import StreamingResponse
import io

app = FastAPI()

@app.get("/")
async def root():
    buf = io.BytesIO(b"hello world")
    buf.seek(0)
    # This might fail if it's not an iterator
    return StreamingResponse(buf, media_type="text/plain")

if __name__ == "__main__":
    import uvicorn
    import threading
    import time
    import requests

    def run_server():
        uvicorn.run(app, host="127.0.0.1", port=8001)

    t = threading.Thread(target=run_server, daemon=True)
    t.start()
    time.sleep(2)

    try:
        r = requests.get("http://127.0.0.1:8001/")
        print(f"Status: {r.status_code}")
        print(f"Content: {r.text}")
    except Exception as e:
        print(f"Error: {e}")
