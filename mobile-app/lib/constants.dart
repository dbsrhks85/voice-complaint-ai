// ────────────────────────────────────────────────────────────
// constants.dart
// 앱 전체에서 사용하는 메시지 상수 모음
// 메시지 수정이 필요할 때 이 파일만 수정하면 됩니다.
// ────────────────────────────────────────────────────────────

class AppMessages {
  AppMessages._(); // 인스턴스 생성 방지

  // ── GPS / 위치 관련 ─────────────────────────────────────
  static const String locationLoading      = '현재 위치를 불러오는 중...';
  static const String locationServiceOff   = '위치 서비스가 비활성화되어 있습니다.\n기기 설정에서 위치를 켜주세요.';
  static const String locationPermDenied   = '위치 권한이 거부되었습니다.';
  static const String locationPermForever  = '위치 권한이 영구 거부되었습니다.\n앱 설정에서 권한을 허용해주세요.';
  static const String locationFailed       = '위치 정보를 가져오지 못했습니다.';

  // ── 녹음 상태 메시지 (스낵바) ───────────────────────────
  static const String recordingAutoStop    = '말씀이 끝나서 자동으로 접수를 준비합니다.';
  static const String recordingManualStop  = '녹음이 완료되었습니다. 인식을 준비합니다...';
  static const String normalizeSuccess     = '음성 파일 준비 완료! 인식 결과를 확인합니다...';
  static const String normalizeFailed      = '음성 파일 준비에 실패했습니다. 원본 파일로 STT를 진행합니다.';

  // ── 캐릭터 상태 메시지 (화면 중앙) ─────────────────────
  static const String idleGuide            = '버튼을 눌러 민원을 말씀해 주세요';
  static const String idleSubGuide         = '음성을 인식하여 자동으로 처리해 드릴게요';
  static const String listeningMain        = '듣고 있어요...';
  static const String analyzingMain        = 'AI가 분석 중이에요...';
  static const String vadGuide             = '듣고 있습니다...\n(2초간 말씀이 없으시면 자동 전송됩니다)';

  // ── 하단 버튼 설명 ──────────────────────────────────────
  static const String hintTapToRecord     = '탭하여 민원 접수 시작';
  static const String hintTapToStop       = '탭하여 녹음 종료';
  static const String labelOriginal       = '원본';
  static const String labelNormalized     = '전송본';
  static const String labelProcessing     = '처리 중';

  // ── STT 결과 다이얼로그 ─────────────────────────────────
  static const String dialogTitle         = 'STT 결과';
  static const String dialogConfirm       = '확인';
  static const String dialogNormalizedFile = '📂 서버 전송 파일';
  static const String dialogOriginalFile  = '📂 원본 파일';
  static const String dialogSavedPath     = '💾 JSON 저장 경로';

  // ── 헤더 UI ─────────────────────────────────────────────
  static const String brandName           = '스마트민원24';
  static const String analyzingBadge      = '분석 중';
  static const String mascotName          = '민원이';
  static const String mascotSubtitle      = 'AI 민원 도우미';

  // ── STT 재확인 흐름 ─────────────────────────────────────
  static const String sttConfirmTitle    = '이렇게 말씀하신 게 맞나요?';
  static const String sttConfirmSubtitle = '아래 내용으로 민원을 접수합니다';
  static const String sttConfirmYes      = '네, 접수할게요';
  static const String sttConfirmNo       = '다시 녹음할게요';
  static const String sttConfirmNoSnack  = '재녹음 모드로 돌아갑니다.';
  static const String sttAnalyzing       = 'AI가 음성을 인식 중이에요...';
  static const String sttSubmitting      = '민원을 접수하는 중이에요...';
  static const String sttSubmitSuccess   = '민원이 정상적으로 접수되었어요! 😊';
  static const String sttSubmitFailed    = '접수 중 오류가 발생했어요. 다시 시도해주세요.';
  static const String sttFetchFailed     = '음성 인식에 실패했어요. 다시 녹음해주세요.';
  static const String submittingBadge    = '접수 중';

  // ── 위치 정보 동의 (현장 민원) ────────────────────────────
  static const String locationConsentTitle   = '현재 위치를 민원에 첨부하시겠습니까?';
  static const String locationConsentSub     = '지도를 이동해 현장 위치를 정중앙에 맞추면 자동으로 좌표가 저장돼요.';
  static const String locationConsentYes     = '예, 위치 첨부';
  static const String locationConsentNo      = '아니오';
  static const String mapPinGuide            = '지도를 이동해 현장 위치를 중앙에 맞춰주세요';
  static const String mapPinConfirmed        = '📍 위치가 설정되었습니다';
  static const String locationGpsWaiting     = '현재 위치를 불러오는 중...';
}
