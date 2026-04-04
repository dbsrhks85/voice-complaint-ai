// 음성 파일 정규화 서비스 - FFmpeg Kit을 사용한 앱 사이드 전처리
// Whisper STT에 최적화된 포맷으로 음성 파일을 변환합니다.
import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

class AudioNormalizer {
  /// 음성 파일을 Whisper STT에 최적화된 WAV로 정규화
  ///
  /// 처리 항목:
  /// 1. 볼륨 정규화 — loudnorm 필터 (EBU R128 표준)
  /// 2. 샘플레이트 — 16kHz 통일
  /// 3. 채널 — 모노 변환
  /// 4. 무음 트리밍 — silenceremove 필터 (앞뒤 무음 제거)
  /// 5. WAV 변환 — Whisper 최적 포맷
  ///
  /// 반환: 정규화된 파일 경로 (실패 시 null)
  static Future<String?> normalizeAudio(String inputPath) async {
    try {
      // 입력 파일 존재 확인
      final inputFile = File(inputPath);
      if (!await inputFile.exists()) {
        print('[정규화] 입력 파일을 찾을 수 없습니다: $inputPath');
        return null;
      }

      // 출력 경로 생성 (원본명_normalized.wav)
      final directory = inputFile.parent.path;
      final baseName = inputPath.split('/').last.split('.').first;
      final outputPath = '$directory/${baseName}_normalized.wav';

      // 이전 정규화 파일이 있으면 삭제
      final outputFile = File(outputPath);
      if (await outputFile.exists()) {
        await outputFile.delete();
      }

      // FFmpeg 명령어 구성
      // 1) loudnorm: EBU R128 표준 볼륨 정규화
      // 2) -ar 16000: 샘플레이트 16kHz
      // 3) -ac 1: 모노 채널
      // (기존의 silenceremove 필터가 문장 중간에 약간만 쉬어도 녹음을 완전히 잘라버리는 문제가 있어 제거)
      final command = '-i "$inputPath" '
          '-af "loudnorm=I=-16:TP=-1.5:LRA=11" '
          '-ar 16000 -ac 1 '
          '-y "$outputPath"';

      print('[정규화] FFmpeg 실행: $command');

      // FFmpeg 실행
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        // 성공 — 파일 크기 확인
        final normalizedFile = File(outputPath);
        if (await normalizedFile.exists()) {
          final size = await normalizedFile.length();
          print('[정규화] 완료 — 파일: $outputPath (${(size / 1024).toStringAsFixed(1)}KB)');
          return outputPath;
        }
      }

      // 실패 시 로그 출력
      final logs = await session.getLogsAsString();
      print('[정규화] FFmpeg 실패: $logs');
      return null;
    } catch (e) {
      print('[정규화] 오류 발생: $e');
      return null;
    }
  }

  /// 정규화된 임시 파일 삭제
  static Future<void> cleanup(String? normalizedPath) async {
    if (normalizedPath == null) return;
    try {
      final file = File(normalizedPath);
      if (await file.exists()) {
        await file.delete();
        print('[정규화] 임시 파일 삭제: $normalizedPath');
      }
    } catch (e) {
      print('[정규화] 임시 파일 삭제 실패: $e');
    }
  }
}
