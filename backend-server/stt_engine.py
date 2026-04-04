# STT 엔진 - OpenAI Whisper API를 사용한 음성→텍스트 변환
import os
from openai import OpenAI
from dotenv import load_dotenv

load_dotenv()
client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))


async def transcribe_audio(file_path: str) -> dict:
    """
    음성 파일을 받아 OpenAI Whisper API로 텍스트 변환

    Args:
        file_path: 음성 파일 경로 (m4a, wav, mp3 등)
    
    Returns:
        {"text": "변환된 텍스트", "success": True/False, "error": "에러 메시지"}
    """
    try:
        # 파일 존재 여부 확인
        if not os.path.exists(file_path):
            return {"text": "", "success": False, "error": "파일을 찾을 수 없습니다."}

        # Whisper API 호출 (한국어 최적화)
        with open(file_path, "rb") as audio_file:
            transcript = client.audio.transcriptions.create(
                model="whisper-1",
                file=audio_file,
                language="ko",  # 한국어 인식 최적화
                response_format="text"
            )

        # 빈 결과 체크
        if not transcript or transcript.strip() == "":
            return {"text": "", "success": False, "error": "음성을 인식하지 못했습니다."}

        return {"text": transcript.strip(), "success": True, "error": None}

    except Exception as e:
        return {"text": "", "success": False, "error": f"STT 처리 중 오류 발생: {str(e)}"}
