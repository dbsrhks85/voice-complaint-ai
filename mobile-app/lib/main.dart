import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:geolocator/geolocator.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'services/audio_normalizer.dart';

// ────────────────────────────────────────────────
// 에뮬레이터에서 PC 호스트(localhost)를 가리키는 주소
// ────────────────────────────────────────────────
const String _kServerUrl = 'http://10.0.2.2:8000';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI 민원 시스템',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
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

class _MainScreenState extends State<MainScreen> {
  String _locationMessage = "현재 위치를 불러오는 중...";
  bool _isRecording = false;
  
  late final AudioRecorder _audioRecorder;
  late final AudioPlayer _audioPlayer;
  bool _initialized = false;
  String? _filePath;
  String? _normalizedFilePath;
  bool _isNormalizing = false;

  // STT 전송 상태
  bool _isSendingSTT = false;
  String? _sttSavedDir; // JSON 저장 디렉토리 경로 (결과 안내용)

  // VAD(침묵 감지)를 위한 변수들
  StreamSubscription<Amplitude>? _amplitudeSub;
  int _silenceCounter = 0;
  final double _silenceThreshold = -35.0; // 조용한 상태를 판별할 데시벨 (필요시 조절)
  final int _maxSilenceFrames = 20; // 100ms * 20 = 2초간 침묵 시 자동 종료

  @override
  void initState() {
    super.initState();
    // UI가 먼저 렌더링된 뒤에 초기화 수행
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeApp();
    });
  }

  /// 오디오 레코더/플레이어 초기화 + 위치 가져오기 (UI 렌더링 이후 실행)
  Future<void> _initializeApp() async {
    _audioRecorder = AudioRecorder();
    _audioPlayer = AudioPlayer();
    _initialized = true;
    await _determinePosition();
  }

  @override
  void dispose() {
    _amplitudeSub?.cancel(); // 메모리 누수 방지
    if (_initialized) {
      _audioRecorder.dispose();
      _audioPlayer.dispose();
    }
    super.dispose();
  }

  Future<void> _determinePosition() async {
    try {
      // 1. 위치 서비스 활성화 확인
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _locationMessage = "위치 서비스가 비활성화되어 있습니다.\n기기 설정에서 위치를 켜주세요.");
        return;
      }

      // 2. 위치 권한 확인 및 요청
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _locationMessage = "위치 권한이 거부되었습니다.");
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() => _locationMessage = "위치 권한이 영구 거부되었습니다.\n앱 설정에서 권한을 허용해주세요.");
        return;
      }

      // 3. 위치 가져오기
      setState(() => _locationMessage = "현재 위치를 불러오는 중...");

      // Android에서는 LocationSettings를 명시적으로 지정
      late LocationSettings locationSettings;
      if (defaultTargetPlatform == TargetPlatform.android) {
        locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
          forceLocationManager: true, // FusedLocationProvider 대신 LocationManager 사용
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
      setState(() {
        _locationMessage = "위도: ${position.latitude}\n경도: ${position.longitude}";
      });
    } catch (e) {
      setState(() => _locationMessage = "위치 정보를 가져오지 못했습니다.\n($e)");
    }
  }

  // 녹음 시작/중단 통합 컨트롤러
  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording(isAutoStopped: false);
    } else {
      await _startRecording();
    }
  }

  // 🎙️ 1. 녹음 시작 및 VAD 적용
  Future<void> _startRecording() async {
    if (await _audioRecorder.hasPermission()) {
      final directory = await getApplicationDocumentsDirectory();
      final path = '${directory.path}/report_${DateTime.now().millisecondsSinceEpoch}.m4a';
      
      // 16kHz, Mono 고정 (Whisper AI 최적화 및 노이즈 방지)
      const config = RecordConfig(
        encoder: AudioEncoder.aacLc, 
        sampleRate: 44100,
        numChannels: 1, 
        bitRate: 32000,
      );
      
      await _audioPlayer.stop();
      await _audioRecorder.start(config, path: path);
      
      setState(() {
        _isRecording = true;
        _filePath = null;
        _normalizedFilePath = null;
        _locationMessage = "듣고 있습니다...\n(2초간 말씀이 없으시면 자동 전송됩니다)";
      });

      // VAD(침묵 감지) 모니터링 시작 (0.1초마다 볼륨 체크)
      _silenceCounter = 0;
      _amplitudeSub = _audioRecorder.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((amp) {
        if (amp.current < _silenceThreshold) {
          _silenceCounter++;
          if (_silenceCounter >= _maxSilenceFrames) {
            _stopRecording(isAutoStopped: true); // 2초 연속 침묵 시 강제 종료
          }
        } else {
          _silenceCounter = 0; // 소리가 들리면 카운터 초기화
        }
      });
    }
  }

  // ⏹️ 2. 녹음 종료 + 정규화 실행
  Future<void> _stopRecording({required bool isAutoStopped}) async {
    _amplitudeSub?.cancel(); // 볼륨 감지 중단
    final path = await _audioRecorder.stop();

    setState(() {
      _isRecording = false;
      _filePath = path;
      _normalizedFilePath = null;
      _isNormalizing = true;
      _determinePosition(); // 화면을 다시 원래 GPS 좌표로 복구
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(isAutoStopped ? "말씀이 끝나서 자동으로 접수를 준비합니다." : "녹음이 완료되었습니다. 정규화 중...")),
    );

    // 녹음 완료 후 음성 정규화 실행
    if (path != null) {
      final normalizedPath = await AudioNormalizer.normalizeAudio(path);
      setState(() {
        _normalizedFilePath = normalizedPath;
        _isNormalizing = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(normalizedPath != null
                ? '음성 정규화 완료! STT 서버로 전송 중...'
                : '정규화 실패 — 원본 파일로 STT 진행합니다.'),
          ),
        );
      }
    } else {
      setState(() => _isNormalizing = false);
    }

    // 녹음 완료 → STT 테스트 전송 (원본 & 정규화 파일 각각)
    _runSttTests(originalPath: path, normalizedPath: _normalizedFilePath);
  }

  // ─────────────────────────────────────────────────────────
  // 🚀 3. STT: 정규화 파일 우선 전송
  //         (정규화 실패 시 원본 파일로 폴백)
  // ─────────────────────────────────────────────────────────
  Future<void> _runSttTests({
    required String? originalPath,
    required String? normalizedPath,
  }) async {
    if (originalPath == null) return;

    setState(() => _isSendingSTT = true);

    final directory = await getApplicationDocumentsDirectory();
    _sttSavedDir = directory.path;

    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .substring(0, 19);

    // 정규화 파일 우선, 없으면 원본 사용
    final filePath = normalizedPath ?? originalPath;
    final label = normalizedPath != null ? 'normalized' : 'original';

    final result = await _sendAudioToSTT(
      filePath: filePath,
      label: label,
    );
    await _saveResultJson(
      result: result,
      label: label,
      filePath: filePath,
      timestamp: timestamp,
      saveDir: directory.path,
    );

    setState(() => _isSendingSTT = false);

    if (mounted) {
      _showSttResultDialog(
        result: result,
        label: label,
        savedDir: directory.path,
        timestamp: timestamp,
      );
    }
  }

  /// 음성 파일을 /upload-audio 로 전송하고 STT 결과 Map 반환
  Future<Map<String, dynamic>> _sendAudioToSTT({
    required String filePath,
    required String label,
  }) async {
    try {
      final dio = Dio();
      final fileName = filePath.split('/').last;

      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          filePath,
          filename: fileName,
        ),
        'lat': '37.0', // 테스트용 임시 좌표
        'lng': '127.0',
      });

      print('[STT-$label] 전송 시작: $filePath');
      final response = await dio.post(
        '$_kServerUrl/upload-audio',
        data: formData,
        options: Options(receiveTimeout: const Duration(seconds: 60)),
      );

      print('[STT-$label] 응답: ${response.data}');
      return Map<String, dynamic>.from(response.data as Map);
    } catch (e) {
      print('[STT-$label] 전송 실패: $e');
      return {
        'success': false,
        'stt_text': '',
        'error': e.toString(),
      };
    }
  }

  /// STT 결과를 JSON 파일로 저장
  Future<void> _saveResultJson({
    required Map<String, dynamic> result,
    required String label,
    required String filePath,
    required String timestamp,
    required String saveDir,
  }) async {
    final payload = {
      'label': label,
      'file': filePath.split('/').last,
      'timestamp': timestamp,
      'success': result['success'],
      'stt_text': result['stt_text'] ?? '',
      'category': result['report']?['category'],
      'department': result['report']?['department'],
      'error': result['error'],
    };

    final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);
    final savePath = '$saveDir/stt_result_${label}_$timestamp.json';
    await File(savePath).writeAsString(jsonStr, flush: true);
    print('[STT-$label] JSON 저장 완료: $savePath');
  }

  /// STT 결과 다이얼로그 표시
  void _showSttResultDialog({
    required Map<String, dynamic>? result,
    required String label,
    required String savedDir,
    required String timestamp,
  }) {
    final text = result?['stt_text'] ?? '(없음)';
    final ok = result?['success'] == true;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🎙️ STT 결과', style: TextStyle(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label == 'normalized' ? '📂 정규화 파일' : '📂 원본 파일 (정규화 실패)',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: label == 'normalized' ? Colors.deepPurple : Colors.orange,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                ok ? text : '❌ 실패: ${result?["error"]}',
                style: TextStyle(color: ok ? Colors.black87 : Colors.red),
              ),
              const Divider(height: 24),
              const Text('💾 JSON 저장 경로', style: TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 4),
              Text(
                '$savedDir/stt_result_${label}_$timestamp.json',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  // 🔊 원본 녹음 재생
  Future<void> _playRecording() async {
    if (_filePath != null) {
      try {
        await _audioPlayer.stop(); 
        await _audioPlayer.setSource(DeviceFileSource(_filePath!)); 
        await _audioPlayer.resume(); 
      } catch (e) {
        print("재생 에러: $e");
      }
    }
  }

  // 🔊 정규화된 녹음 재생
  Future<void> _playNormalizedRecording() async {
    if (_normalizedFilePath != null) {
      try {
        await _audioPlayer.stop();
        await _audioPlayer.setSource(DeviceFileSource(_normalizedFilePath!));
        await _audioPlayer.resume();
      } catch (e) {
        print("정규화 재생 에러: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blueAccent,
        title: const Text('AI 음성 민원 접수', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: Colors.grey[200],
              width: double.infinity,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_isRecording ? Icons.mic : Icons.location_on, size: 60, color: _isRecording ? Colors.red : Colors.blueAccent),
                  const SizedBox(height: 16),
                  Text(_locationMessage, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: _toggleRecording,
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: _isRecording ? Colors.red : Colors.blue,
                    child: Icon(_isRecording ? Icons.stop : Icons.mic, color: Colors.white, size: 40),
                  ),
                ),
                if (!_isRecording && _filePath != null) ...[
                  const SizedBox(width: 20),
                  // 원본 재생 버튼 (초록)
                  GestureDetector(
                    onTap: _playRecording,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircleAvatar(
                          radius: 30,
                          backgroundColor: Colors.green,
                          child: Icon(Icons.play_arrow, color: Colors.white),
                        ),
                        const SizedBox(height: 4),
                        Text('원본', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  // 정규화 재생 버튼 (보라) 또는 로딩 인디케이터
                  if (_isNormalizing)
                    const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: Colors.grey,
                          child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)),
                        ),
                        SizedBox(height: 4),
                        Text('처리 중...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    )
                  else if (_normalizedFilePath != null)
                    GestureDetector(
                      onTap: _playNormalizedRecording,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircleAvatar(
                            radius: 30,
                            backgroundColor: Colors.deepPurple,
                            child: Icon(Icons.play_arrow, color: Colors.white),
                          ),
                          const SizedBox(height: 4),
                          Text('정규화', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          )
        ],
      ),
    );
  }
}