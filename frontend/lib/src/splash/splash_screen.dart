// lib/src/splash/splash_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../core/theme.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onDone;
  const SplashScreen({super.key, required this.onDone});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _fade;
  late Animation<double>   _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _fade  = CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.6, curve: Curves.easeOut));
    _scale = Tween<double>(begin: 0.82, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.6, curve: Curves.easeOutBack)));

    _ctrl.forward();

    Timer(const Duration(milliseconds: 2600), widget.onDone);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Center(
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo mark
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      image: const DecorationImage(
                        image: AssetImage('assets/icon.png'),
                        fit: BoxFit.cover,
                      ),
                      border: Border.all(color: AppTheme.border, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.accent.withOpacity(0.2),
                          blurRadius: 40,
                          spreadRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  // Title
                  Text.rich(
                    TextSpan(
                      text: 'PHONE ',
                      style: const TextStyle(color: AppTheme.bad),
                      children: const [
                        TextSpan(
                          text: 'PATHOLOGY',
                          style: TextStyle(color: AppTheme.textPri),
                        ),
                      ],
                    ),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Quality Testing Suite',
                    style: TextStyle(
                      color: AppTheme.textSec,
                      fontSize: 13,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 48),
                  // Pulse dot
                  _PulseDot(controller: _ctrl),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  final AnimationController controller;
  const _PulseDot({required this.controller});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) => Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppTheme.accent.withOpacity(0.4 + 0.6 * _pulse.value),
        ),
      ),
    );
  }
}
