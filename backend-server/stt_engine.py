# STT 엔진 - OpenAI Whisper API를 사용한 음성→텍스트 변환
import asyncio
import os
import shutil
import subprocess
import uuid
from openai import AsyncOpenAI
from dotenv import load_dotenv
from messages import SttMessages

load_dotenv()
# [Fix #7] AsyncOpenAI 클라이언트로 전환 (async 함수 내 동기 호출 블로킹 방지)
client = AsyncOpenAI(api_key=os.getenv("OPENAI_API_KEY"))
STT_PROMPT = (
    "한국어 민원 신고 음성입니다. 사용자는 생활 불편, 시설물 고장, "
    "도로, 쓰레기, 소음, 안전 문제 등을 자연스럽게 설명합니다."
)
PROMPT_LEAK_PHRASES = (
    "한국어 민원 신고 음성입니다",
    "사용자는 생활 불편",
    "사용자의 시설물 고장",
    "시설물 고장, 도로, 쓰레기, 소음, 안전 문제",
    "자연스럽게 설명합니다",
)


def _env_flag(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def _is_suspicious_transcript(text: str) -> bool:
    normalized = text.strip()
    if not normalized:
        return True
    if any(phrase in normalized for phrase in PROMPT_LEAK_PHRASES):
        return True
    if "시설물 고장" in normalized and "자연스럽게" in normalized:
        return True
    if len(normalized) <= 4:
        return True

    filler_chars = set("ㅎㅋㅠㅜㅗㅓㅏㅣㅡ .,!?\n\r\t")
    return all(char in filler_chars for char in normalized)


def _normalize_audio_sync(input_path: str) -> str | None:
    """FFmpeg가 있으면 Whisper용 WAV 파일로 정규화하고, 실패하면 None을 반환."""
    if not _env_flag("STT_NORMALIZE_AUDIO", True):
        print("[stt] server normalization disabled. Using original audio.")
        return None

    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        print("[stt] ffmpeg not found. Using original audio.")
        return None

    directory = os.path.dirname(input_path)
    output_path = os.path.join(directory, f"normalized_{uuid.uuid4().hex}.wav")
    command = [
        ffmpeg,
        "-hide_banner",
        "-loglevel",
        "error",
        "-y",
        "-i",
        input_path,
        "-af",
        "loudnorm=I=-16:TP=-1.5:LRA=11",
        "-ar",
        "16000",
        "-ac",
        "1",
        output_path,
    ]

    try:
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )
        if result.returncode == 0 and os.path.exists(output_path):
            print(f"[stt] audio normalized on server: {output_path}")
            return output_path

        print(f"[stt] ffmpeg normalization failed: {result.stderr.strip()}")
        if os.path.exists(output_path):
            os.remove(output_path)
        return None
    except Exception as e:
        print(f"[stt] ffmpeg normalization error: {e}")
        if os.path.exists(output_path):
            os.remove(output_path)
        return None


async def normalize_audio_for_stt(input_path: str) -> str | None:
    return await asyncio.to_thread(_normalize_audio_sync, input_path)


async def _transcribe_file(file_path: str) -> str:
    with open(file_path, "rb") as audio_file:
        transcript = await client.audio.transcriptions.create(
            model="whisper-1",
            file=audio_file,
            language="ko",
            prompt=STT_PROMPT,
            response_format="text",
            temperature=0,
        )
    return transcript.strip() if transcript else ""


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
            return {"text": "", "success": False, "error": SttMessages.FILE_NOT_FOUND}

        original_size = os.path.getsize(file_path)
        print(f"[stt] original audio received: {file_path} ({original_size} bytes)")

        stt_file_path = await normalize_audio_for_stt(file_path)
        file_to_transcribe = stt_file_path or file_path
        transcript = await _transcribe_file(file_to_transcribe)
        try:
            if (
                stt_file_path
                and _env_flag("STT_RETRY_ORIGINAL_ON_SUSPICIOUS", True)
                and _is_suspicious_transcript(transcript)
            ):
                print(
                    "[stt] suspicious normalized transcript. "
                    f"Retrying original audio: {transcript!r}"
                )
                original_transcript = await _transcribe_file(file_path)
                if original_transcript:
                    transcript = original_transcript
        finally:
            if (
                stt_file_path
                and os.path.exists(stt_file_path)
                and not _env_flag("STT_KEEP_NORMALIZED_AUDIO", False)
            ):
                os.remove(stt_file_path)

        # 빈 결과 또는 프롬프트 누출/무의미한 결과 체크
        if not transcript or transcript.strip() == "":
            return {"text": "", "success": False, "error": SttMessages.EMPTY_TRANSCRIPT}
        if _is_suspicious_transcript(transcript):
            print(f"[stt] rejected suspicious transcript: {transcript!r}")
            return {"text": "", "success": False, "error": SttMessages.EMPTY_TRANSCRIPT}

        return {"text": transcript.strip(), "success": True, "error": None}

    except Exception as e:
        return {"text": "", "success": False, "error": SttMessages.PROCESSING_ERROR.format(error=str(e))}
