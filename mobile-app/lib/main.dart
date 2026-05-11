import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:geolocator/geolocator.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:io';
import 'dart:async';
import 'services/audio_normalizer.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'models/app_user.dart';
import 'constants.dart';
import 'config.dart'; // ← 서버 주소는 config.dart에서 관리 (git 제외)
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kakao_map_plugin/kakao_map_plugin.dart';
import 'map_picker_page.dart';

bool _firebaseReady = false;

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!_firebaseReady) {
    try {
      await Firebase.initializeApp();
      _firebaseReady = true;
    } catch (_) {
      return;
    }
  }
}

// ── Cloud Dancer 디자인 시스템 ──────────────────────
class AppColors {
  // Cloud Dancer (PANTONE 11-4201 TCX) 기반 팔레트
  static const Color cloudDancer = Color(0xFFECEAE4); // 메인 배경
  static const Color cloudSoft = Color(0xFFF5F4F0); // 카드 배경
  static const Color cloudDeep = Color(0xFFD8D4CB); // 구분선/보더
  static const Color cloudWarm = Color(0xFFC8C3B5); // 비활성 아이콘

  // 포인트 컬러 (민원이 넥타이 & 배지의 스틸 블루)
  static const Color accentBlue = Color(0xFF3A6EA5); // 주 액션
  static const Color accentLight = Color(0xFF5B8FCC); // 호버/강조
  static const Color accentDeep = Color(0xFF254E82); // 헤더

  // 상태 컬러
  static const Color recordRed = Color(0xFFE05252); // 녹음 중
  static const Color successGreen = Color(0xFF4A9E7F); // 성공
  static const Color textDark = Color(0xFF2C2C2C); // 기본 텍스트
  static const Color textMid = Color(0xFF6E6B62); // 보조 텍스트
  static const Color textLight = Color(0xFF9E9B93); // 힌트 텍스트
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    _firebaseReady = true;
  } catch (e) {
    debugPrint('Firebase 초기화 실패: $e');
  }

  // 카카오 로그인 SDK 초기화
  KakaoSdk.init(
    nativeAppKey: kKakaoNativeAppKey,
    javaScriptAppKey: kKakaoMapApiKey,
  );

  // 카카오맵 플러그인 초기화 (JavaScript Key 사용)
  AuthRepository.initialize(appKey: kKakaoMapApiKey);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI 민원 시스템',
      theme: ThemeData(
        fontFamily: 'Pretendard',
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.accentBlue,
          background: AppColors.cloudDancer,
        ),
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  final String _kServerUrl = kServerUrl; // config.dart에서 서버 주소 참조

  // 로그인 상태
  bool _isLoggedIn = false;
  bool _isAuthRestoring = true;
  bool _isLoggingIn = false;
  AppUser? _currentUser;
  List<Map<String, dynamic>> _myReports = [];
  bool _isLoadingMyReports = false;
  String? _pushToken;
  StreamSubscription<String>? _pushTokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundMessageSub;
  StreamSubscription<RemoteMessage>? _messageOpenedSub;

  String _locationMessage = AppMessages.locationLoading;
  bool _isRecording = false;

  late final AudioRecorder _audioRecorder;
  late final AudioPlayer _audioPlayer;
  late final AuthService _authService;
  late final ApiClient _apiClient;
  bool _initialized = false;
  String? _filePath;
  String? _normalizedFilePath;
  bool _isNormalizing = false;

  // STT 전송 상태
  bool _isSendingSTT = false;

  // STT 재확인 흐름을 위한 상태
  bool _isSubmitting = false; // NLP + DB 접수 처리 중 여부
  Position? _currentPosition; // 최신 GPS 위치 (민원 제출 시 활용)

  // VAD(침묵 감지)를 위한 변수들
  StreamSubscription<Amplitude>? _amplitudeSub;
  int _silenceCounter = 0;
  final double _silenceThreshold = -35.0;
  final int _maxSilenceFrames = 20;

  // 애니메이션 컨트롤러
  late AnimationController _pulseController;
  late AnimationController _waveController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _waveAnimation;

  @override
  void initState() {
    super.initState();
    _authService = AuthService(serverUrl: _kServerUrl);
    _apiClient = ApiClient(baseUrl: _kServerUrl, authService: _authService);

    // 맥동 애니메이션 (녹음 버튼)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // 파형 애니메이션 (음파 이펙트)
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _waveAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _waveController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeApp();
    });
  }

  Future<void> _initializeApp() async {
    _audioRecorder = AudioRecorder();
    _audioPlayer = AudioPlayer();
    _initialized = true;
    await _initializePushNotifications();
    await _restoreAuthSession();
    // GPS 자동 취득 제거 — 현장 민원 위치 동의 시점에만 취득
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _waveController.dispose();
    _amplitudeSub?.cancel();
    _pushTokenRefreshSub?.cancel();
    _foregroundMessageSub?.cancel();
    _messageOpenedSub?.cancel();
    if (_initialized) {
      _audioRecorder.dispose();
      _audioPlayer.dispose();
    }
    super.dispose();
  }

  // ── 카카오 로그인 로직 ──────────────────────────────────────
  Future<void> _loginWithKakao() async {
    if (_isLoggingIn) return;
    setState(() => _isLoggingIn = true);
    try {
      final session = await _authService.loginWithKakao();
      setState(() {
        _isLoggedIn = true;
        _currentUser = session.user;
        _isLoggingIn = false;
      });
      _showSnack('${_kakaoNickname(_currentUser)}님 환영합니다!');
      await _registerPushToken();

      // 로그인 후 서버에 유저 정보 등록 (옵션)
      // _registerUserToServer(user);
    } catch (e) {
      if (mounted) {
        setState(() => _isLoggingIn = false);
      }
      debugPrint('카카오 로그인 에러: $e');
      _showSnack('카카오 로그인에 실패했습니다.');
    }
  }

  Future<void> _restoreAuthSession() async {
    try {
      final session = await _authService.restoreSession();
      if (!mounted) return;
      if (session != null) {
        setState(() {
          _isLoggedIn = true;
          _currentUser = session.user;
          _isAuthRestoring = false;
        });
        await _registerPushToken();
      } else {
        setState(() => _isAuthRestoring = false);
      }
    } catch (e) {
      debugPrint('로그인 세션 복원 실패: $e');
      if (mounted) {
        setState(() => _isAuthRestoring = false);
      }
    }
  }

  Future<void> _logout() async {
    await _authService.logout();
    if (!mounted) return;
    setState(() {
      _isLoggedIn = false;
      _currentUser = null;
      _myReports = [];
    });
    _showSnack('로그아웃되었습니다.');
  }

  Future<void> _initializePushNotifications() async {
    if (!_firebaseReady) {
      debugPrint('Firebase가 초기화되지 않아 푸쉬 알림을 비활성화합니다.');
      return;
    }

    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      debugPrint('푸쉬 알림 권한 상태: ${settings.authorizationStatus}');

      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      _pushToken = await messaging.getToken();
      debugPrint('FCM token: $_pushToken');
      if (_isLoggedIn && _currentUser != null) {
        await _registerPushToken();
      }

      _pushTokenRefreshSub = messaging.onTokenRefresh.listen((token) async {
        _pushToken = token;
        if (_isLoggedIn && _currentUser != null) {
          await _registerPushToken();
        }
      });

      _foregroundMessageSub = FirebaseMessaging.onMessage.listen((message) {
        final title = message.notification?.title ?? '민원 상태 알림';
        final body = message.notification?.body ?? '민원 상태가 변경되었습니다.';
        if (mounted) {
          _showSnack('$title\n$body');
        }
      });

      _messageOpenedSub = FirebaseMessaging.onMessageOpenedApp.listen((_) {
        if (_isLoggedIn) {
          _openMyReportsSheet();
        }
      });

      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null && mounted && _isLoggedIn) {
        _openMyReportsSheet();
      }
    } catch (e) {
      debugPrint('푸쉬 알림 초기화 실패: $e');
    }
  }

  Future<void> _registerPushToken() async {
    if (!_isLoggedIn || _pushToken == null || _pushToken!.isEmpty) return;

    try {
      final formData = FormData.fromMap({'push_token': _pushToken});

      await _apiClient.dio.post(
        '/me/push-token',
        data: formData,
        options: Options(receiveTimeout: const Duration(seconds: 15)),
      );
      debugPrint('푸쉬 토큰 등록 완료');
    } catch (e) {
      debugPrint('푸쉬 토큰 등록 실패: $e');
    }
  }

  Future<void> _determinePosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _locationMessage = AppMessages.locationServiceOff);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _locationMessage = AppMessages.locationPermDenied);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() => _locationMessage = AppMessages.locationPermForever);
        return;
      }

      setState(() => _locationMessage = AppMessages.locationLoading);

      late LocationSettings locationSettings;
      if (defaultTargetPlatform == TargetPlatform.android) {
        locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
          forceLocationManager: true,
        );
      } else {
        locationSettings = const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        );
      }

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: locationSettings,
      );
      final address = await _reverseGeocode(
        position.latitude,
        position.longitude,
      );
      setState(() {
        _currentPosition = position;
        _locationMessage = address ?? '현재 위치 주소를 찾지 못했습니다.';
      });
    } catch (e) {
      setState(() => _locationMessage = '${AppMessages.locationFailed}\n($e)');
    }
  }

  Future<void> _toggleRecording() async {
    if (_isSendingSTT || _isSubmitting) return; // 처리 중에는 새 녹음 불가
    if (_isRecording) {
      await _stopRecording(isAutoStopped: false);
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    if (await _audioRecorder.hasPermission()) {
      final directory = await getApplicationDocumentsDirectory();
      final path =
          '${directory.path}/report_${DateTime.now().millisecondsSinceEpoch}.wav';

      const config = RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      );

      await _audioPlayer.stop();
      await _audioRecorder.start(config, path: path);

      setState(() {
        _isRecording = true;
        _filePath = null;
        _normalizedFilePath = null;
        _locationMessage = AppMessages.vadGuide;
      });

      _silenceCounter = 0;
      _amplitudeSub = _audioRecorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((amp) {
            if (amp.current < _silenceThreshold) {
              _silenceCounter++;
              if (_silenceCounter >= _maxSilenceFrames) {
                _stopRecording(isAutoStopped: true);
              }
            } else {
              _silenceCounter = 0;
            }
          });
    }
  }

  Future<void> _stopRecording({required bool isAutoStopped}) async {
    _amplitudeSub?.cancel();
    final path = await _audioRecorder.stop();

    setState(() {
      _isRecording = false;
      _filePath = path;
      _normalizedFilePath = null;
      _isNormalizing = true;
      _determinePosition();
    });

    _showSnack(
      isAutoStopped
          ? AppMessages.recordingAutoStop
          : AppMessages.recordingManualStop,
    );

    if (path != null) {
      final normalizedPath = await AudioNormalizer.normalizeAudio(path);
      setState(() {
        _normalizedFilePath = normalizedPath;
        _isNormalizing = false;
      });

      if (mounted) {
        _showSnack(
          normalizedPath != null
              ? AppMessages.normalizeSuccess
              : AppMessages.normalizeFailed,
        );
      }
    } else {
      setState(() => _isNormalizing = false);
    }

    // 정규화 파일(없으면 원본)을 서버에 보내 STT 텍스트 추출
    final fileToSend = _normalizedFilePath ?? path;
    if (fileToSend != null && mounted) {
      await _fetchSttOnly(filePath: fileToSend);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: AppColors.accentBlue,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    );
  }

  String _kakaoNickname(AppUser? user) {
    final nickname = user?.nickname.trim();
    return (nickname == null || nickname.isEmpty) ? '사용자' : nickname;
  }

  bool _isValidLatLng(double? lat, double? lng) {
    return lat != null &&
        lng != null &&
        lat.isFinite &&
        lng.isFinite &&
        lat >= -90 &&
        lat <= 90 &&
        lng >= -180 &&
        lng <= 180;
  }

  Future<String?> _reverseGeocode(double lat, double lng) async {
    if (!_isValidLatLng(lat, lng)) {
      debugPrint('주소 변환 생략: 유효하지 않은 좌표 lat=$lat, lng=$lng');
      return null;
    }

    try {
      final response = await _apiClient.dio.get(
        '/reverse-geocode',
        queryParameters: {'lat': lat, 'lng': lng},
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );
      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['success'] == false) return null;
      final address = data['address']?.toString().trim();
      return (address == null || address.isEmpty) ? null : address;
    } catch (e) {
      debugPrint('주소 변환 실패: $e');
      return null;
    }
  }

  String _reportStatusLabel(String? status) {
    switch (status) {
      case 'pending':
        return '민원 접수 중';
      case 'processing':
        return '민원 처리 중';
      case 'completed':
        return '민원 처리 완료';
      case 'rejected':
        return '민원 반려';
      default:
        return '상태 확인 중';
    }
  }

  Color _reportStatusColor(String? status) {
    switch (status) {
      case 'pending':
        return AppColors.accentBlue;
      case 'processing':
        return const Color(0xFF5B7FBA);
      case 'completed':
        return AppColors.successGreen;
      case 'rejected':
        return AppColors.recordRed;
      default:
        return AppColors.textMid;
    }
  }

  IconData _reportStatusIcon(String? status) {
    switch (status) {
      case 'pending':
        return Icons.hourglass_empty_rounded;
      case 'processing':
        return Icons.settings_suggest_outlined;
      case 'completed':
        return Icons.check_circle_outline;
      case 'rejected':
        return Icons.error_outline_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }

  String _formatReportDate(dynamic raw) {
    if (raw == null) return '-';
    try {
      final date = DateTime.parse(raw.toString()).toLocal();
      final month = date.month.toString().padLeft(2, '0');
      final day = date.day.toString().padLeft(2, '0');
      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');
      return '$month.$day $hour:$minute';
    } catch (_) {
      return raw.toString();
    }
  }

  Future<List<Map<String, dynamic>>> _fetchMyReports() async {
    if (!_isLoggedIn) return [];

    final response = await _apiClient.dio.get(
      '/me/reports',
      options: Options(receiveTimeout: const Duration(seconds: 20)),
    );

    final data = response.data;
    if (data is List) {
      return data
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
    return [];
  }

  Future<void> _openMyReportsSheet() async {
    if (!_isLoggedIn || _currentUser == null) {
      _showSnack('로그인 후 내 민원 현황을 확인할 수 있어요.');
      return;
    }
    if (_isLoadingMyReports) return;

    setState(() => _isLoadingMyReports = true);
    try {
      final reports = await _fetchMyReports();
      if (!mounted) return;
      setState(() {
        _myReports = reports;
        _isLoadingMyReports = false;
      });
      _showMyReportsBottomSheet();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingMyReports = false);
      _showSnack('내 민원 현황을 불러오지 못했습니다.');
    }
  }

  void _showMyReportsBottomSheet() {
    String selectedStatus = 'pending';
    final statuses = ['pending', 'processing', 'completed', 'rejected'];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final filtered = _myReports
              .where((report) => report['status'] == selectedStatus)
              .toList();

          return Container(
            height: MediaQuery.of(context).size.height * 0.82,
            decoration: const BoxDecoration(
              color: AppColors.cloudSoft,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: EdgeInsets.fromLTRB(
              20,
              14,
              20,
              MediaQuery.of(context).padding.bottom + 20,
            ),
            child: Column(
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: AppColors.cloudDeep,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Row(
                  children: [
                    const Icon(
                      Icons.list_alt_rounded,
                      color: AppColors.accentBlue,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '내 민원 현황',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppColors.textMid,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: statuses.map((status) {
                      final count = _myReports
                          .where((r) => r['status'] == status)
                          .length;
                      final selected = selectedStatus == status;
                      final color = _reportStatusColor(status);
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text('${_reportStatusLabel(status)} $count'),
                          selected: selected,
                          selectedColor: color.withOpacity(0.16),
                          backgroundColor: AppColors.cloudDancer,
                          labelStyle: TextStyle(
                            color: selected ? color : AppColors.textMid,
                            fontWeight: selected
                                ? FontWeight.w800
                                : FontWeight.w600,
                            fontSize: 12,
                          ),
                          side: BorderSide(
                            color: selected
                                ? color.withOpacity(0.45)
                                : AppColors.cloudDeep,
                          ),
                          onSelected: (_) =>
                              setModalState(() => selectedStatus = status),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            '${_reportStatusLabel(selectedStatus)} 민원이 없습니다.',
                            style: const TextStyle(
                              color: AppColors.textMid,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final report = filtered[index];
                            final status = report['status']?.toString();
                            final color = _reportStatusColor(status);
                            final title = report['title']?.toString().trim();
                            final address = report['address']
                                ?.toString()
                                .trim();
                            final rejectionReason = report['rejection_reason']
                                ?.toString()
                                .trim();

                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.cloudDancer,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppColors.cloudDeep),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 9,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: color.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              _reportStatusIcon(status),
                                              size: 13,
                                              color: color,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              _reportStatusLabel(status),
                                              style: TextStyle(
                                                color: color,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        _formatReportDate(report['created_at']),
                                        style: const TextStyle(
                                          color: AppColors.textLight,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    (title == null || title.isEmpty)
                                        ? '제목 없음'
                                        : title,
                                    style: const TextStyle(
                                      color: AppColors.textDark,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 7),
                                  Text(
                                    (address == null || address.isEmpty)
                                        ? '주소 정보 없음'
                                        : address,
                                    style: const TextStyle(
                                      color: AppColors.textMid,
                                      fontSize: 12,
                                      height: 1.35,
                                    ),
                                  ),
                                  if (status == 'rejected' &&
                                      rejectionReason != null &&
                                      rejectionReason.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: AppColors.recordRed.withOpacity(
                                          0.08,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: AppColors.recordRed
                                              .withOpacity(0.2),
                                        ),
                                      ),
                                      child: Text(
                                        '반려 사유: $rejectionReason',
                                        style: const TextStyle(
                                          color: AppColors.recordRed,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  // [Step 1]  /stt-only  →  STT 텍스트만 받아오기
  // ──────────────────────────────────────────────────────────
  Future<void> _fetchSttOnly({required String filePath}) async {
    setState(() => _isSendingSTT = true);

    try {
      final fileName = filePath.split('/').last;
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
      });

      final response = await _apiClient.dio.post(
        '/stt-only',
        data: formData,
        options: Options(receiveTimeout: const Duration(seconds: 60)),
      );

      final result = Map<String, dynamic>.from(response.data as Map);
      setState(() => _isSendingSTT = false);

      if (!mounted) return;

      if (result['success'] == true) {
        final sttText = result['stt_text'] as String? ?? '';
        if (sttText.isEmpty) {
          _showSnack(AppMessages.sttFetchFailed);
          return;
        }
        // GPT 분류 결과 파싱 (없으면 기본값 사용)
        final nlp = result['nlp'] as Map<String, dynamic>?;
        _showSttConfirmBottomSheet(
          sttText: sttText,
          suggestedType: nlp?['complaint_type'] as String? ?? 'field',
          nlpTitle: nlp?['title'] as String?,
          nlpCategory: nlp?['category'] as String?,
          nlpDepartment: nlp?['department'] as String?,
        );
      } else {
        _showSnack(result['error']?.toString() ?? AppMessages.sttFetchFailed);
      }
    } catch (e) {
      setState(() => _isSendingSTT = false);
      _showSnack(AppMessages.sttFetchFailed);
    }
  }

  // ──────────────────────────────────────────────────────────
  // [Step 2]  바텀시트 — STT 결과 사용자 재확인
  // ──────────────────────────────────────────────────────────
  void _showSttConfirmBottomSheet({
    required String sttText,
    String suggestedType = 'field', // GPT 제안 민원 유형
    String? nlpTitle,               // GPT 제안 제목
    String? nlpCategory,            // GPT 제안 카테고리
    String? nlpDepartment,          // GPT 제안 담당부서
  }) {
    String currentType = suggestedType; // GPT 제안값으로 토글 초기화
    List<File> attachedFiles = [];
    final TextEditingController textController = TextEditingController(
      text: sttText,
    );

    // 위치 관련 상태
    bool locationConsented = false;
    bool isLoadingGps = false;
    double? selectedLat;
    double? selectedLng;
    String? selectedAddress;
    const double defaultLat = 37.8813; // 춘천시청 기본 좌표
    const double defaultLng = 127.7298;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setModalState) {
          Future<void> onConsentYes() async {
            setModalState(() {
              locationConsented = true;
              isLoadingGps = true;
            });
            await _determinePosition();
            final initLat = _currentPosition?.latitude ?? defaultLat;
            final initLng = _currentPosition?.longitude ?? defaultLng;
            final address = await _reverseGeocode(initLat, initLng);
            setModalState(() {
              selectedLat = initLat;
              selectedLng = initLng;
              selectedAddress = address;
              isLoadingGps = false;
            });
          }

          return Container(
            decoration: const BoxDecoration(
              color: AppColors.cloudSoft,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: EdgeInsets.fromLTRB(
              24,
              16,
              24,
              MediaQuery.of(context).viewInsets.bottom + 36,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: AppColors.cloudDeep,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Text(
                    AppMessages.sttConfirmTitle,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "아래 민원 내용을 확인하고 알맞은 유형을 선택해주세요.",
                    style: TextStyle(fontSize: 13, color: AppColors.textMid),
                  ),
                  const SizedBox(height: 20),

                  // ── 유형 선택 토글
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ChoiceChip(
                        label: const Text('📍 현장 민원'),
                        selected: currentType == 'field',
                        selectedColor: AppColors.accentBlue.withOpacity(0.2),
                        onSelected: (_) => setModalState(() {
                          currentType = 'field';
                        }),
                      ),
                      const SizedBox(width: 12),
                      ChoiceChip(
                        label: const Text('📄 행정 민원'),
                        selected: currentType == 'admin',
                        selectedColor: AppColors.accentBlue.withOpacity(0.2),
                        onSelected: (_) => setModalState(() {
                          currentType = 'admin';
                          locationConsented = false;
                          selectedLat = null;
                          selectedLng = null;
                          selectedAddress = null;
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── 민원 텍스트 편집 필드
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.cloudDancer,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.cloudDeep),
                    ),
                    child: TextField(
                      controller: textController,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(18),
                        hintText: '수정할 민원 내용을 입력하세요',
                      ),
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.textDark,
                        fontWeight: FontWeight.w500,
                        height: 1.65,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── 현장 민원 전용: 위치 첨부 섹션
                  if (currentType == 'field') ...[
                    if (!locationConsented) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.accentBlue.withOpacity(0.07),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppColors.accentBlue.withOpacity(0.25),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              AppMessages.locationConsentTitle,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textDark,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              AppMessages.locationConsentSub,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textMid,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: onConsentYes,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.accentBlue,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                      ),
                                      elevation: 0,
                                    ),
                                    child: const Text(
                                      AppMessages.locationConsentYes,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () {},
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.textMid,
                                      side: const BorderSide(
                                        color: AppColors.cloudDeep,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                      ),
                                    ),
                                    child: const Text(
                                      AppMessages.locationConsentNo,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      if (isLoadingGps)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.accentBlue,
                                ),
                              ),
                              SizedBox(width: 10),
                              Text(
                                AppMessages.locationGpsWaiting,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textMid,
                                ),
                              ),
                            ],
                          ),
                        )
                      else ...[
                        // ── 위치 선택 완료 여부에 따라 다른 UI 표시
                        if (selectedLat == null) ...[
                          // 지도 열기 버튼
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final result = await Navigator.push<LatLng>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => MapPickerPage(
                                      initialLat:
                                          _currentPosition?.latitude ??
                                          defaultLat,
                                      initialLng:
                                          _currentPosition?.longitude ??
                                          defaultLng,
                                    ),
                                  ),
                                );
                                if (result != null) {
                                  if (!_isValidLatLng(
                                    result.latitude,
                                    result.longitude,
                                  )) {
                                    _showSnack('지도 좌표를 확인하지 못했습니다. 다시 시도해주세요.');
                                    return;
                                  }
                                  setModalState(() {
                                    isLoadingGps = true;
                                  });
                                  final address = await _reverseGeocode(
                                    result.latitude,
                                    result.longitude,
                                  );
                                  setModalState(() {
                                    selectedLat = result.latitude;
                                    selectedLng = result.longitude;
                                    selectedAddress = address;
                                    isLoadingGps = false;
                                  });
                                }
                              },
                              icon: const Icon(Icons.map_outlined, size: 20),
                              label: const Text(
                                '지도에서 위치 선택하기',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.accentBlue,
                                side: const BorderSide(
                                  color: AppColors.accentBlue,
                                  width: 1.5,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                            ),
                          ),
                        ] else ...[
                          // 위치 선택 완료 표시
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE05252).withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFE05252).withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.location_pin,
                                  color: Color(0xFFE05252),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        AppMessages.mapPinConfirmed,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFFE05252),
                                        ),
                                      ),
                                      Text(
                                        selectedAddress ?? '주소를 찾지 못했습니다.',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textMid,
                                          height: 1.35,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // 위치 재선택 버튼
                                TextButton(
                                  onPressed: () async {
                                    final result = await Navigator.push<LatLng>(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => MapPickerPage(
                                          initialLat: selectedLat!,
                                          initialLng: selectedLng!,
                                        ),
                                      ),
                                    );
                                    if (result != null) {
                                      if (!_isValidLatLng(
                                        result.latitude,
                                        result.longitude,
                                      )) {
                                        _showSnack(
                                          '지도 좌표를 확인하지 못했습니다. 다시 시도해주세요.',
                                        );
                                        return;
                                      }
                                      setModalState(() {
                                        isLoadingGps = true;
                                      });
                                      final address = await _reverseGeocode(
                                        result.latitude,
                                        result.longitude,
                                      );
                                      setModalState(() {
                                        selectedLat = result.latitude;
                                        selectedLng = result.longitude;
                                        selectedAddress = address;
                                        isLoadingGps = false;
                                      });
                                    }
                                  },
                                  child: const Text(
                                    '변경',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.accentBlue,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // 위치 선택 취소
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => setModalState(() {
                                locationConsented = false;
                                selectedLat = null;
                                selectedLng = null;
                                selectedAddress = null;
                              }),
                              child: const Text(
                                '위치 선택 취소',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textMid,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ],
                    const SizedBox(height: 8),
                  ],

                  // ── 파일 첨부
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () async {
                        final picker = ImagePicker();
                        final XFile? result = await picker.pickImage(
                          source: ImageSource.gallery,
                        );
                        if (result != null) {
                          setModalState(
                            () => attachedFiles.add(File(result.path)),
                          );
                        }
                      },
                      icon: const Icon(
                        Icons.attach_file,
                        size: 20,
                        color: AppColors.textMid,
                      ),
                      label: const Text(
                        '파일/사진 첨부하기 (선택)',
                        style: TextStyle(color: AppColors.textMid),
                      ),
                    ),
                  ),
                  if (attachedFiles.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12, bottom: 8),
                        child: Text(
                          '첨부됨: ${attachedFiles.last.path.split('/').last}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.accentBlue,
                          ),
                        ),
                      ),
                    ),

                  const SizedBox(height: 24),

                  // ── 접수 버튼
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        final hasValidLocation = _isValidLatLng(
                          selectedLat,
                          selectedLng,
                        );
                        _submitComplaintWithText(
                          sttText: textController.text,
                          complaintType: currentType,
                          attachedFiles: attachedFiles,
                          selectedLat:
                              (currentType == 'field' &&
                                  locationConsented &&
                                  hasValidLocation)
                              ? selectedLat
                              : null,
                          selectedLng:
                              (currentType == 'field' &&
                                  locationConsented &&
                                  hasValidLocation)
                              ? selectedLng
                              : null,
                          selectedAddress:
                              (currentType == 'field' &&
                                  locationConsented &&
                                  hasValidLocation)
                              ? selectedAddress
                              : null,
                          nlpTitle: nlpTitle,
                          nlpCategory: nlpCategory,
                          nlpDepartment: nlpDepartment,
                        );
                      },
                      icon: const Icon(Icons.check_circle_outline, size: 20),
                      label: const Text(
                        AppMessages.sttConfirmYes,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accentBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── 재녹음 버튼
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        setState(() {
                          _filePath = null;
                          _normalizedFilePath = null;
                        });
                        _showSnack(AppMessages.sttConfirmNoSnack);
                      },
                      icon: const Icon(Icons.mic_outlined, size: 20),
                      label: const Text(
                        AppMessages.sttConfirmNo,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textMid,
                        side: const BorderSide(
                          color: AppColors.cloudDeep,
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  // [Step 3]  /submit-complaint  →  최종 확인 텍스트를 GPT 분석 + DB 저장
  // ──────────────────────────────────────────────────────────
  Future<void> _submitComplaintWithText({
    required String sttText,
    String? complaintType,
    List<File> attachedFiles = const [],
    double? selectedLat,     // 사용자가 지도 핀으로 선택한 위도 (field+동의 시)
    double? selectedLng,     // 사용자가 지도 핀으로 선택한 경도 (field+동의 시)
    String? selectedAddress,
    String? nlpTitle,        // GPT 분류 제안 제목 (서버 GPT 재실행 방지)
    String? nlpCategory,     // GPT 분류 제안 카테고리
    String? nlpDepartment,   // GPT 분류 제안 담당부서
  }) async {
    setState(() => _isSubmitting = true);

    try {
      final hasValidLocation = _isValidLatLng(selectedLat, selectedLng);
      // 위치 정보: field+동의 시 드래그 좌표, admin 또는 거절 시 null
      final mapData = <String, dynamic>{
        'stt_text': sttText,
        if (hasValidLocation) 'lat': selectedLat.toString(),
        if (hasValidLocation) 'lng': selectedLng.toString(),
        if (hasValidLocation &&
            selectedAddress != null &&
            selectedAddress.isNotEmpty)
          'address': selectedAddress,
        if (complaintType != null) 'complaint_type': complaintType,
        // GPT 분류 결과 전달 → 서버에서 GPT 재실행 불필요
        if (nlpTitle != null) 'title': nlpTitle,
        if (nlpCategory != null) 'category': nlpCategory,
        if (nlpDepartment != null) 'department': nlpDepartment,
      };

      if (attachedFiles.isNotEmpty) {
        mapData['attachments'] = [
          await MultipartFile.fromFile(
            attachedFiles.first.path,
            filename: attachedFiles.first.path.split('/').last,
          ),
        ];
      }

      final formData = FormData.fromMap(mapData);

      final response = await _apiClient.dio.post(
        '/submit-complaint',
        data: formData,
        options: Options(receiveTimeout: const Duration(seconds: 30)),
      );

      final result = Map<String, dynamic>.from(response.data as Map);

      setState(() {
        _isSubmitting = false;
        _filePath = null;
        _normalizedFilePath = null;
      });

      if (!mounted) return;

      if (result['success'] == true) {
        _showSnack(AppMessages.sttSubmitSuccess);
      } else {
        _showSnack(AppMessages.sttSubmitFailed);
      }
    } catch (e) {
      setState(() => _isSubmitting = false);
      _showSnack(AppMessages.sttSubmitFailed);
    }
  }

  Future<void> _playRecording() async {
    if (_filePath != null) {
      try {
        await _audioPlayer.stop();
        await _audioPlayer.setSource(DeviceFileSource(_filePath!));
        await _audioPlayer.resume();
      } catch (e) {
        debugPrint("재생 에러: $e");
      }
    }
  }

  Future<void> _playNormalizedRecording() async {
    if (_normalizedFilePath != null) {
      try {
        await _audioPlayer.stop();
        await _audioPlayer.setSource(DeviceFileSource(_normalizedFilePath!));
        await _audioPlayer.resume();
      } catch (e) {
        debugPrint("정규화 재생 에러: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cloudDancer,
      body: SafeArea(
        child: Stack(
          children: [
            // ── Layer 1: 민원이 캐릭터 (배경색 위, UI 아래) ────────
            Positioned.fill(
              child: Align(
                alignment: const Alignment(0, -0.45), // 화면 위쪽으로 더 올림
                child: AnimatedBuilder(
                  animation: _isRecording
                      ? _pulseAnimation
                      : const AlwaysStoppedAnimation(1.0),
                  builder: (context, child) => Transform.scale(
                    scale: _isRecording ? _pulseAnimation.value : 1.0,
                    child: child,
                  ),
                  child: Builder(
                    builder: (context) {
                      // 화면 너비의 190%를 최대값으로 제한 (2배 크기)
                      final size = (MediaQuery.of(context).size.width * 1.9)
                          .clamp(0.0, 1120.0);
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          // 녹음 중 파동 이펙트
                          if (_isRecording)
                            AnimatedBuilder(
                              animation: _waveAnimation,
                              builder: (context, _) => Container(
                                width: size + 60 + (_waveAnimation.value * 48),
                                height: size + 60 + (_waveAnimation.value * 48),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.recordRed.withOpacity(
                                    0.07 - _waveAnimation.value * 0.05,
                                  ),
                                ),
                              ),
                            ),
                          // 민원이 이미지 (화면 너비 기준 4배 크기)
                          Image.asset(
                            'assets/images/minwoni_clouddancer_sizeup.png',
                            width: size,
                            height: size,
                            fit: BoxFit.contain,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),

            // ── Layer 2: UI 레이아웃 (헤더, 카드, 버튼) ──────────
            Column(
              children: [
                _buildHeader(),
                Expanded(child: _buildCenterContent()),
                _buildLocationCard(),
                _buildBottomPanel(),
              ],
            ),

            // ── Layer 3: 로그인 오버레이 (로그인 안 된 경우 덮어씌움) ──
            if (!_isLoggedIn)
              Positioned.fill(
                child: Container(
                  color: AppColors.cloudDancer.withOpacity(0.95), // 반투명 배경
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.lock_outline,
                          size: 60,
                          color: AppColors.accentBlue,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _isAuthRestoring
                              ? '로그인 상태를\n확인하고 있습니다.'
                              : '서비스 이용을 위해\n로그인이 필요합니다.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDark,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 32),
                        ElevatedButton(
                          onPressed: (_isAuthRestoring || _isLoggingIn)
                              ? null
                              : _loginWithKakao,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFEE500), // 카카오 노란색
                            foregroundColor: Colors.black87,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 40,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isLoggingIn || _isAuthRestoring)
                                const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black87,
                                  ),
                                )
                              else
                                const Icon(Icons.chat_bubble_rounded, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                _isAuthRestoring
                                    ? '확인 중'
                                    : _isLoggingIn
                                    ? '로그인 중'
                                    : '카카오로 3초만에 시작하기',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── 헤더 ──────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: _openMyReportsSheet,
            child: Container(
              width: 36,
              height: 36,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: AppColors.cloudSoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.cloudDeep),
              ),
              child: _isLoadingMyReports
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.accentBlue,
                      ),
                    )
                  : const Icon(
                      Icons.menu_rounded,
                      color: AppColors.accentBlue,
                      size: 20,
                    ),
            ),
          ),
          // 앱 로고/이름
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.accentBlue,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.smart_toy_outlined, color: Colors.white, size: 14),
                SizedBox(width: 5),
                Text(
                  AppMessages.brandName,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          if (_isLoggedIn)
            IconButton(
              tooltip: '로그아웃',
              onPressed: _logout,
              icon: const Icon(
                Icons.logout_rounded,
                color: AppColors.accentBlue,
                size: 20,
              ),
            ),
          // 처리 중 인디케이터 (STT 인식 중 / 민원 접수 중)
          if (_isSendingSTT || _isSubmitting)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.accentBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.accentBlue.withOpacity(0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.accentBlue,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isSubmitting
                        ? AppMessages.submittingBadge
                        : AppMessages.analyzingBadge,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.accentBlue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── 캐릭터 배지 + 상태 메시지 (캐릭터는 Stack 레이어에서 별도 렌더링) ─
  Widget _buildCenterContent() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end, // 하단 정렬 → 캐릭터 발 아래에 위치
      children: [
        // 캐릭터 이름 배지
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.accentBlue,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.accentBlue.withOpacity(0.25),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified_outlined, size: 12, color: Colors.white70),
              SizedBox(width: 5),
              Text(
                AppMessages.mascotName,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(width: 5),
              Text(
                AppMessages.mascotSubtitle,
                style: TextStyle(color: Colors.white70, fontSize: 10),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // 상태 메시지 카드
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.cloudSoft.withOpacity(
              0.92,
            ), // 살짝 투명 → 캐릭터가 은은하게 비침
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.cloudDeep),
          ),
          child: Column(
            children: [
              if (_isRecording) ...[
                // 파형 애니메이션 바
                AnimatedBuilder(
                  animation: _waveAnimation,
                  builder: (context, _) => _buildWaveBars(),
                ),
                const SizedBox(height: 10),
              ],
              Text(
                _isRecording
                    ? AppMessages.listeningMain
                    : _isSendingSTT
                    ? AppMessages.sttAnalyzing
                    : _isSubmitting
                    ? AppMessages.sttSubmitting
                    : AppMessages.idleGuide,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _isRecording
                      ? AppColors.recordRed
                      : AppColors.textDark,
                ),
              ),
              if (!_isRecording && !_isSendingSTT && !_isSubmitting)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    AppMessages.idleSubGuide,
                    style: TextStyle(fontSize: 11, color: AppColors.textLight),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // 파형 바 시각화
  Widget _buildWaveBars() {
    final heights = [
      0.4,
      0.7,
      1.0,
      0.6,
      0.9,
      0.5,
      0.8,
      0.4,
      0.7,
      1.0,
      0.6,
      0.5,
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(heights.length, (i) {
        final phase = (_waveAnimation.value + i * 0.15) % 1.0;
        final h = (heights[i] * 0.5 + phase * 0.5).clamp(0.2, 1.0);
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          width: 4,
          height: 24 * h,
          decoration: BoxDecoration(
            color: AppColors.recordRed.withOpacity(0.6 + h * 0.4),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  // ── GPS 카드 ──────────────────────────────────────────────
  Widget _buildLocationCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cloudSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cloudDeep),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.accentBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.location_on_outlined,
              color: AppColors.accentBlue,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _locationMessage,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textMid,
                height: 1.4,
              ),
            ),
          ),
          GestureDetector(
            onTap: _determinePosition,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.cloudDeep.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.refresh,
                size: 14,
                color: AppColors.textMid,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 하단 버튼 패널 ─────────────────────────────────────────
  Widget _buildBottomPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      decoration: BoxDecoration(
        color: AppColors.cloudSoft,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: AppColors.cloudDeep, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 드래그 핸들
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: AppColors.cloudDeep,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // 버튼 행
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // 원본 재생 버튼
              if (!_isRecording &&
                  !_isSendingSTT &&
                  !_isSubmitting &&
                  _filePath != null)
                _buildPlayButton(
                  onTap: _playRecording,
                  label: '원본',
                  icon: Icons.volume_up_outlined,
                  color: AppColors.successGreen,
                  size: 52,
                ),

              if (!_isRecording &&
                  !_isSendingSTT &&
                  !_isSubmitting &&
                  _filePath != null)
                const SizedBox(width: 16),

              // 메인 녹음 버튼
              _buildMainRecordButton(),

              if (!_isRecording &&
                  !_isSendingSTT &&
                  !_isSubmitting &&
                  _filePath != null)
                const SizedBox(width: 16),

              // 정규화 재생 버튼
              if (!_isRecording &&
                  !_isSendingSTT &&
                  !_isSubmitting &&
                  _filePath != null)
                _isNormalizing
                    ? _buildLoadingButton(size: 52)
                    : (_normalizedFilePath != null
                          ? _buildPlayButton(
                              onTap: _playNormalizedRecording,
                              label: AppMessages.labelNormalized,
                              icon: Icons.tune_outlined,
                              color: AppColors.accentBlue,
                              size: 52,
                            )
                          : const SizedBox(width: 52)),
            ],
          ),

          const SizedBox(height: 12),

          // 버튼 설명 레이블
          Text(
            _isRecording
                ? AppMessages.hintTapToStop
                : AppMessages.hintTapToRecord,
            style: const TextStyle(fontSize: 11, color: AppColors.textLight),
          ),
        ],
      ),
    );
  }

  // 메인 녹음/정지 버튼
  Widget _buildMainRecordButton() {
    return GestureDetector(
      onTap: _toggleRecording,
      child: AnimatedBuilder(
        animation: _isRecording
            ? _pulseAnimation
            : const AlwaysStoppedAnimation(1.0),
        builder: (context, child) {
          return Transform.scale(
            scale: _isRecording ? _pulseAnimation.value : 1.0,
            child: child,
          );
        },
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _isRecording
                  ? [AppColors.recordRed, Color(0xFFC03030)]
                  : [AppColors.accentLight, AppColors.accentBlue],
            ),
            boxShadow: [
              BoxShadow(
                color:
                    (_isRecording ? AppColors.recordRed : AppColors.accentBlue)
                        .withOpacity(0.35),
                blurRadius: 16,
                spreadRadius: 2,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(
            _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
            color: Colors.white,
            size: 34,
          ),
        ),
      ),
    );
  }

  // 재생 버튼 (원본 / 정규화)
  Widget _buildPlayButton({
    required VoidCallback onTap,
    required String label,
    required IconData icon,
    required Color color,
    required double size,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.1),
              border: Border.all(color: color.withOpacity(0.4), width: 1.5),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: AppColors.textMid,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // 로딩 버튼 (정규화 처리 중)
  Widget _buildLoadingButton({required double size}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.cloudDeep.withOpacity(0.3),
            border: Border.all(color: AppColors.cloudDeep, width: 1.5),
          ),
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.accentBlue,
              ),
            ),
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          AppMessages.labelProcessing,
          style: TextStyle(fontSize: 10, color: AppColors.textLight),
        ),
      ],
    );
  }
}
