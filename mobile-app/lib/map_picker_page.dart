import 'package:flutter/material.dart';
import 'package:kakao_map_plugin/kakao_map_plugin.dart';

/// 전체화면 지도 위치 선택 페이지
/// - 스크롤 컨테이너가 없어 지도 드래그가 방해받지 않음
/// - 중앙 고정 핀 + onCameraIdle로 좌표 취득
/// - 확인 버튼 탭 시 LatLng 반환
class MapPickerPage extends StatefulWidget {
  final double initialLat;
  final double initialLng;

  const MapPickerPage({
    super.key,
    required this.initialLat,
    required this.initialLng,
  });

  @override
  State<MapPickerPage> createState() => _MapPickerPageState();
}

class _MapPickerPageState extends State<MapPickerPage> {
  late double _selectedLat;
  late double _selectedLng;
  bool _isMapMoving = false;

  @override
  void initState() {
    super.initState();
    _selectedLat = widget.initialLat;
    _selectedLng = widget.initialLng;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── 1. 전체화면 카카오맵 (스크롤 충돌 없음)
          KakaoMap(
            center: LatLng(widget.initialLat, widget.initialLng),
            onMapCreated: (controller) {},
            onDragChangeCallback: (latLng, zoomLevel, dragType) {
              // 지도 이동 시작/중 — 핀 살짝 위로 float
              if (!_isMapMoving) {
                setState(() => _isMapMoving = true);
              }
            },
            onCameraIdle: (latLng, zoomLevel) {
              // 지도 멈춤 — 중앙 좌표 저장
              setState(() {
                _selectedLat = latLng.latitude;
                _selectedLng = latLng.longitude;
                _isMapMoving = false;
              });
            },
          ),

          // ── 2. 상단 앱바 오버레이
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              padding: EdgeInsets.fromLTRB(
                16,
                MediaQuery.of(context).padding.top + 8,
                16,
                20,
              ),
              child: Row(
                children: [
                  // 뒤로가기
                  GestureDetector(
                    onTap: () => Navigator.pop(context, null),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    '현장 위치 지정',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── 3. 중앙 고정 핀 (지도 이동 시 살짝 위로 float)
          AnimatedAlign(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.center,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              margin: EdgeInsets.only(bottom: _isMapMoving ? 60 : 44),
              child: AnimatedScale(
                duration: const Duration(milliseconds: 200),
                scale: _isMapMoving ? 1.15 : 1.0,
                child: const Icon(
                  Icons.location_pin,
                  color: Color(0xFFE05252),
                  size: 48,
                  shadows: [
                    Shadow(
                      color: Colors.black38,
                      offset: Offset(0, 3),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── 4. 하단 위치 안내 + 확인 버튼
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              padding: EdgeInsets.fromLTRB(
                20,
                30,
                20,
                MediaQuery.of(context).padding.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 안내 문구
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '지도를 이동해 현장 위치를 📍 중앙에 맞춰주세요',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '중앙 핀 위치가 주소로 저장됩니다',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.78),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 확인 버튼
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(
                        context,
                        LatLng(_selectedLat, _selectedLng),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE05252),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        '이 위치로 확인',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
