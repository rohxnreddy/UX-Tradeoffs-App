// lib/src/auth/login_screen.dart
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../core/session_store.dart';
import '../core/theme.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback onLoggedIn;
  const LoginScreen({super.key, required this.onLoggedIn});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);
  bool _loading = false;
  String? _error;

  late AnimationController _fadeCtrl;
  late Animation<double>   _fade;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() { _loading = true; _error = null; });
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) {
        setState(() { _loading = false; _error = 'Sign-in cancelled'; });
        return;
      }
      SessionStore.instance.setAuth(
        name:     account.displayName ?? account.email,
        email:    account.email,
        photoUrl: account.photoUrl,
      );
      widget.onLoggedIn();
    } catch (e) {
      setState(() { _loading = false; _error = 'Sign-in failed: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: FadeTransition(
        opacity: _fade,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                const Spacer(flex: 2),
                // Icon
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.surface,
                    border: Border.all(color: AppTheme.border),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.accent.withOpacity(0.15),
                        blurRadius: 30,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.lock_outline,
                      color: AppTheme.accent, size: 32),
                ),
                const SizedBox(height: 32),
                // Heading
                const Text(
                  'Sign in to continue',
                  style: TextStyle(
                    color: AppTheme.textPri,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Your organisation credentials are used\nto associate test results with your device.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.textSec,
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
                const Spacer(flex: 2),
                // Google button
                _GoogleButton(
                  loading: _loading,
                  onTap: _loading ? null : _signIn,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: const TextStyle(color: AppTheme.bad, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
                const Spacer(),
                // Footer
                const Text(
                  'Test data is stored securely and\nused only for quality research.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.textDim,
                    fontSize: 12,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  final bool loading;
  final VoidCallback? onTap;
  const _GoogleButton({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: loading ? 0.5 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: loading
              ? const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.accent,
                    ),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Google G icon — drawn with coloured circles
                    _GoogleIcon(),
                    const SizedBox(width: 14),
                    const Text(
                      'Continue with Google',
                      style: TextStyle(
                        color: AppTheme.textPri,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _GoogleIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(painter: _GooglePainter()),
    );
  }
}

class _GooglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r  = size.width / 2;

    final colors = [
      const Color(0xFF4285F4), // blue
      const Color(0xFF34A853), // green
      const Color(0xFFFBBC05), // yellow
      const Color(0xFFEA4335), // red
    ];

    final rects = [
      Rect.fromLTWH(cx, cy - r, r, r),          // top-right  blue
      Rect.fromLTWH(cx, cy, r, r),               // bot-right  green
      Rect.fromLTWH(cx - r, cy, r, r),           // bot-left   yellow
      Rect.fromLTWH(cx - r, cy - r, r, r),       // top-left   red
    ];

    for (int i = 0; i < 4; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        i * (3.14159 / 2),
        3.14159 / 2,
        true,
        Paint()..color = colors[i],
      );
    }

    // White circle in centre
    canvas.drawCircle(Offset(cx, cy), r * 0.55, Paint()..color = AppTheme.surface);
  }

  @override
  bool shouldRepaint(_) => false;
}
