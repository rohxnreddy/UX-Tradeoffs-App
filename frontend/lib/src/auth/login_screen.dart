// lib/src/auth/login_screen.dart
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../core/session_store.dart';
import '../core/theme.dart';

// Set to true during local development to skip the Google sign-in UI.
// MUST be false before releasing to testers.
const bool kDevBypassLogin = false;

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
  bool _agreedToPrivacy = false;

  late AnimationController _fadeCtrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();

    // DEV BYPASS — skips the sign-in screen entirely
    if (kDevBypassLogin) {
      Future.microtask(() {
        SessionStore.instance.setAuth(
          name: 'Dev User',
          email: 'dev@test.com',
          photoUrl: null,
        );
        widget.onLoggedIn();
      });
    }

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final account = await _googleSignIn.signIn();

      if (account == null) {
        // User dismissed the picker
        setState(() {
          _loading = false;
          _error = 'Sign-in cancelled';
        });
        return;
      }

      // Store identity in SessionStore so metadata_service can read it later.
      // tester_name  → account.displayName  (used as the human-readable name in DB)
      // tester_email → account.email        (used as unique tester identifier in DB)
      // tester_photo_url → account.photoUrl (stored for dashboard avatars, optional)
      SessionStore.instance.setAuth(
        name: account.displayName ?? account.email,
        email: account.email,
        photoUrl: account.photoUrl,
      );

      widget.onLoggedIn();
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Sign-in failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show a plain spinner while the dev bypass micro-task fires
    if (kDevBypassLogin) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: FadeTransition(
        opacity: _fade,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 3),

                // Premium Icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.surface,
                    border: Border.all(color: AppTheme.border, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.accent.withOpacity(0.2),
                        blurRadius: 40,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.fingerprint,
                    color: AppTheme.accent,
                    size: 38,
                  ),
                ),

                const SizedBox(height: 48),

                // Heading
                const Text(
                  'Sign in to continue',
                  style: TextStyle(
                    color: AppTheme.textPri,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),

                const Spacer(flex: 1),

                // Privacy Policy Tick
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: _agreedToPrivacy,
                        activeColor: AppTheme.accent,
                        checkColor: Colors.black,
                        side: const BorderSide(color: AppTheme.border, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        onChanged: (val) {
                          setState(() {
                            _agreedToPrivacy = val ?? false;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () => _showPrivacyPolicy(context),
                      child: const Text.rich(
                        TextSpan(
                          text: 'I agree to the ',
                          style: TextStyle(color: AppTheme.textSec, fontSize: 13),
                          children: [
                            TextSpan(
                              text: 'Privacy Policy',
                              style: TextStyle(
                                color: AppTheme.accent,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 24),

                // Button
                _GoogleButton(
                  loading: _loading,
                  onTap: (_loading || !_agreedToPrivacy) ? null : _signIn,
                ),

                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: const TextStyle(color: AppTheme.bad, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],

                const Spacer(flex: 3),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showPrivacyPolicy(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Privacy Policy',
                    style: TextStyle(
                      color: AppTheme.textPri,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      children: const [
                        Text(
                          '1. Data Collection\n'
                          'We collect device metadata such as model, brand, OS version, and network performance indicators. We do not inspect personal files or communications.\n\n'
                          '2. Data Usage\n'
                          'Your data is securely stored and exclusively utilized to measure network and device quality. We do not sell your data to third parties.\n\n'
                          '3. Account Identity\n'
                          'We associate your test results with your Google Sign-In identity to maintain a continuous record of your device performance.\n\n'
                          '4. Revocation\n'
                          'You may log out at any time to halt the collection and syncing of data for this session.\n',
                          style: TextStyle(
                            color: AppTheme.textSec,
                            fontSize: 14,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ── Sign-in button ────────────────────────────────────────────────────────────

class _GoogleButton extends StatelessWidget {
  final bool loading;
  final VoidCallback? onTap;

  const _GoogleButton({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    bool disabled = onTap == null && !loading;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: disabled ? 0.35 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border),
          ),
          child: loading
              ? const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppTheme.accent,
                    ),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
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
    final r = size.width / 2;

    final colors = [
      const Color(0xFF4285F4),
      const Color(0xFF34A853),
      const Color(0xFFFBBC05),
      const Color(0xFFEA4335),
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

    // Inner white circle to create the "G" ring effect
    canvas.drawCircle(
      Offset(cx, cy),
      r * 0.55,
      Paint()..color = AppTheme.surface, // Matches the button background
    );
  }

  @override
  bool shouldRepaint(_) => false;
}