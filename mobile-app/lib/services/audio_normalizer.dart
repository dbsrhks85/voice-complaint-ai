// 음성 파일 정규화 서비스
// 실제 오디오 정규화는 서버에서 수행합니다. 모바일 앱은 기기별 네이티브
// FFmpeg 호환성 문제를 피하기 위해 원본 녹음 파일만 서버로 전송합니다.
import 'dart:io';
import 'package:flutter/foundation.dart';

class AudioNormalizer {
  /// 서버 정규화 전환 이후에는 원본 파일 경로를 그대로 반환합니다.
  static Future<String?> normalizeAudio(String inputPath) async {
    try {
      final inputFile = File(inputPath);
      if (!await inputFile.exists()) {
        debugPrint('[정규화] 원본 파일을 찾을 수 없습니다: $inputPath');
        return null;
      }
      debugPrint('[정규화] 서버 정규화 사용 - 원본 파일 전송: $inputPath');
      return inputPath;
    } catch (e) {
      debugPrint('[정규화] 원본 파일 확인 실패: $e');
      return null;
    }
  }

  /// 서버 정규화 전환 이후 앱에서 별도 정규화 파일을 생성하지 않습니다.
  static Future<void> cleanup(String? normalizedPath) async {
    return;
  }
}
