import 'dart:math';
import 'package:flutter/material.dart';
import '../main.dart'; // AppColors 접근용

class IdleWaveform extends StatefulWidget {
  const IdleWaveform({super.key});

  @override
  State<IdleWaveform> createState() => _IdleWaveformState();
}

class _IdleWaveformState extends State<IdleWaveform> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  // 각 바의 기본 높이 비율을 랜덤하게 생성
  final List<double> _baseHeights = List.generate(20, (index) {
    // 중앙으로 갈수록 높아지는 형태
    double dist = (index - 10).abs() / 10.0;
    return (1.0 - dist) * (0.5 + Random().nextDouble() * 0.5);
  });

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(_baseHeights.length, (i) {
            // 물결치는 듯한 애니메이션 계산
            final phase = (_controller.value * 2 * pi) + (i * 0.4);
            final animationFactor = (sin(phase).abs() * 0.6) + 0.4;
            final height = 8 + (32 * _baseHeights[i] * animationFactor);
            
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: 3.5,
              height: height,
              decoration: BoxDecoration(
                color: AppColors.accentBlue.withOpacity(0.5 + (0.3 * animationFactor)),
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        );
      },
    );
  }
}
