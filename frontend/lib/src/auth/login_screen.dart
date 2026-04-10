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
                  width: 90,
                  height: 90,
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
                        color: AppTheme.accent.withOpacity(0.25),
                        blurRadius: 40,
                        spreadRadius: 8,
                      ),
                    ],
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
              child: Column(
                children: [
                  // Handle indicator
                  Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppTheme.border,
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Header
                  const Text(
                    'Participant Information and\nData Use Agreement',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.textPri,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Phone Benchmarking Study',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.accent,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Content
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      physics: const BouncingScrollPhysics(),
                      children: [
                        _PolicySection(
                          title: '1. Purpose of the Study',
                          content: 'This study collects performance data from smartphones to understand how devices perform under real-world conditions, especially across older and used phones. The findings will be used for academic research and may be published in anonymised form.',
                        ),
                        _PolicySection(
                          title: '2. What Data We Collect',
                          content: 'The app will collect the following types of data:',
                          bullets: [
                            'Device information: model, manufacturer, OS version, hardware specifications',
                            'Performance metrics: audio/video playback quality, speech clarity, battery usage, network latency/throughput',
                            'Coarse location (city/region level) to understand geographic variation in ownership and performance',
                            'App interaction data: timestamps, test completion status',
                            'Limited system logs required to compute the above metrics',
                          ],
                        ),
                        _PolicySection(
                          title: 'We do not collect:',
                          bullets: [
                            'personal files (photos, videos, documents)',
                            'contact lists, messages, or call logs',
                            'precise, continuous location tracking beyond what is required for the study',
                            'personally identifiable information unless explicitly stated',
                          ],
                        ),
                        _PolicySection(
                          title: '3. How Data Is Collected',
                          bullets: [
                            'Data is collected only when the benchmarking app is actively used',
                            'Location is captured only at specific points during testing',
                            'No background data collection occurs outside test sessions',
                            'The app does not access unrelated sensors or data sources',
                          ],
                        ),
                        _PolicySection(
                          title: '4. Data Storage and Security',
                          bullets: [
                            'Data is stored on secure servers maintained by BITS Pilani Hyderabad Campus',
                            'Data is transmitted using encrypted channels (HTTPS)',
                            'Access is restricted to authorised members of the research team',
                            'Data is de-identified at the point of storage wherever possible',
                          ],
                        ),
                        _PolicySection(
                          title: '5. How the Data Will Be Used',
                          content: 'Your data will be used for analysing smartphone performance, identifying patterns in device degradation, and publishing research papers.',
                          footer: 'All published results will be aggregated and anonymised. No individual user will be identifiable.',
                        ),
                        _PolicySection(
                          title: '6. Data Sharing and Dataset Release',
                          bullets: [
                            'A de-identified version of the dataset may be released for research purposes',
                            'The dataset will be shared under a non-commercial research licence',
                            'No personally identifiable information will be included',
                            'Location data, if shared, will be coarsened to prevent re-identification',
                          ],
                        ),
                        _PolicySection(
                          title: '7. Who Has Access to the Data',
                          content: 'Access is limited to primary investigators and authorised research staff. Institutional review bodies may audit if required.',
                          footer: 'No commercial entities will have access to raw data.',
                        ),
                        _PolicySection(
                          title: '8. Data Retention',
                          bullets: [
                            'Data will be stored for up to 5 years for research purposes',
                            'After this period, data will be deleted or retained only in fully anonymised form',
                          ],
                        ),
                        _PolicySection(
                          title: '9. Voluntary Participation',
                          bullets: [
                            'Your participation is voluntary; stop using the app at any time',
                            'You may request deletion of your data by contacting the research team',
                          ],
                        ),
                        _PolicySection(
                          title: '10. Contact Information',
                          content: 'For questions or data deletion requests, please contact:',
                          footer: 'Prof. Dipanjan Chakraborty\ndipanjan@hyderabad.bits-pilani.ac.in\nBITS Pilani, Hyderabad Campus',
                        ),
                        _PolicySection(
                          title: '11. Consent',
                          content: 'By using this app, you confirm that you have read and understood this agreement and consent to the collection and use of your data as described above.',
                        ),
                        const SizedBox(height: 60),
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

// ── Helpers ───────────────────────────────────────────────────────────────────

class _PolicySection extends StatelessWidget {
  final String title;
  final String? content;
  final List<String>? bullets;
  final String? footer;

  const _PolicySection({
    required this.title,
    this.content,
    this.bullets,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.textPri,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (content != null) ...[
            const SizedBox(height: 8),
            Text(
              content!,
              style: const TextStyle(
                color: AppTheme.textSec,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
          if (bullets != null) ...[
            const SizedBox(height: 10),
            ...bullets!.map((b) => Padding(
                  padding: const EdgeInsets.only(bottom: 6.0, left: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ', style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold)),
                      Expanded(
                        child: Text(
                          b,
                          style: const TextStyle(color: AppTheme.textSec, fontSize: 13, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
          if (footer != null) ...[
            const SizedBox(height: 8),
            Text(
              footer!,
              style: const TextStyle(
                color: AppTheme.textSec,
                fontSize: 13,
                fontStyle: FontStyle.italic,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
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
                    Image.asset('assets/google.webp', width: 22, height: 22),
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