// lib/src/home/home_screen.dart
import 'package:flutter/material.dart';
import '../core/session_store.dart';
import '../core/theme.dart';
import '../runner/test_model.dart';

class HomeScreen extends StatefulWidget {
  final void Function(List<TestId> selected) onStart;
  final VoidCallback onLogout;
  final VoidCallback onShowHistory;

  const HomeScreen({
    super.key,
    required this.onStart,
    required this.onLogout,
    required this.onShowHistory,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final Set<TestId> _selected = Set.of(TestId.values);

  late AnimationController _fadeCtrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  static const _testNames = {
    TestId.vmaf: 'Video Experience',
    TestId.peaq: 'Audio Quality',
    TestId.pesq: 'Voice Clarity',
    TestId.iqa: 'Camera Quality',
    TestId.battery: 'Battery Health',
  };

  static const _testColors = {
    TestId.vmaf: AppTheme.vmafColor,
    TestId.peaq: AppTheme.peaqColor,
    TestId.pesq: AppTheme.pesqColor,
    TestId.iqa: AppTheme.iqaColor,
    TestId.battery: AppTheme.battColor,
  };

  static const _testIcons = {
    TestId.vmaf: Icons.videocam_outlined,
    TestId.peaq: Icons.music_note_outlined,
    TestId.pesq: Icons.record_voice_over_outlined,
    TestId.iqa: Icons.image_outlined,
    TestId.battery: Icons.battery_charging_full_outlined,
  };

  int get _totalEst => allTests
      .where((t) => _selected.contains(t.id))
      .fold(0, (s, t) => s + t.estimatedSeconds);

  @override
  Widget build(BuildContext context) {
    final store = SessionStore.instance;
    final name = store.googleDisplayName ?? store.googleEmail ?? 'Tester';

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: FadeTransition(
        opacity: _fade,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hey, ${name.split(' ').first} 👋',
                            style: const TextStyle(
                              color: AppTheme.textSec,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Quality Tests',
                            style: TextStyle(
                              color: AppTheme.textPri,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: widget.onShowHistory,
                      icon: const Icon(Icons.history_rounded,
                          color: AppTheme.textPri, size: 24),
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      onSelected: (val) {
                        if (val == 'profile') {
                          _showProfileInfo(context);
                        } else if (val == 'logout') {
                          widget.onLogout();
                        }
                      },
                      offset: const Offset(0, 48),
                      color: AppTheme.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: AppTheme.border),
                      ),
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'profile',
                          child: Row(
                            children: [
                              Icon(Icons.person_outline, size: 20, color: AppTheme.textPri),
                              SizedBox(width: 12),
                              Text('Profile Info', style: TextStyle(color: AppTheme.textPri)),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'logout',
                          child: Row(
                            children: [
                              Icon(Icons.logout, size: 20, color: AppTheme.bad),
                              SizedBox(width: 12),
                              Text('Logout', style: TextStyle(color: AppTheme.bad, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ],
                      child: store.googlePhotoUrl != null
                          ? CircleAvatar(
                              radius: 20,
                              backgroundImage: NetworkImage(store.googlePhotoUrl!),
                            )
                          : Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppTheme.surface,
                                border: Border.all(color: AppTheme.border),
                              ),
                              child: const Icon(Icons.person,
                                  color: AppTheme.textSec, size: 20),
                            ),
                    ),
                  ],
                ),
              ),


              const SizedBox(height: 28),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    _InfoChip(
                      icon: Icons.timer_outlined,
                      label: '~${_totalEst}s total',
                      color: AppTheme.accent,
                    ),
                    const SizedBox(width: 8),
                    _InfoChip(
                      icon: Icons.check_box_outlined,
                      label: '${_selected.length} tests selected',
                      color: AppTheme.good,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: allTests.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final def = allTests[i];
                    final color = _testColors[def.id]!;
                    final icon = _testIcons[def.id]!;
                    final checked = _selected.contains(def.id);
                    final displayName =
                        _testNames[def.id] ?? def.title;

                    return _TestCard(
                      title: displayName,
                      definition: def,
                      color: color,
                      icon: icon,
                      checked: checked,
                      onToggle: () {
                        setState(() {
                          if (checked) {
                            _selected.remove(def.id);
                          } else {
                            _selected.add(def.id);
                          }
                        });
                      },
                    );
                  },
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                child: AnimatedOpacity(
                  opacity: _selected.isEmpty ? 0.35 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: GestureDetector(
                    onTap: _selected.isEmpty
                        ? null
                        : () => widget.onStart(_selected.toList()),
                    child: Container(
                      width: double.infinity,
                      height: 58,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.accent, AppTheme.accentDim],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.accent.withOpacity(0.3),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.play_arrow_rounded,
                              color: Colors.black, size: 26),
                          SizedBox(width: 10),
                          Text(
                            'START ALL TESTS',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showProfileInfo(BuildContext context) {
    final store = SessionStore.instance;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.fromLTRB(28, 16, 28, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            Row(
              children: [
                if (store.googlePhotoUrl != null)
                  CircleAvatar(
                    radius: 28,
                    backgroundImage: NetworkImage(store.googlePhotoUrl!),
                  )
                else
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.surface,
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: const Icon(Icons.person, color: AppTheme.textSec, size: 28),
                  ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        store.googleDisplayName ?? 'Tester',
                        style: const TextStyle(
                          color: AppTheme.textPri,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        store.googleEmail ?? 'No email available',
                        style: const TextStyle(
                          color: AppTheme.textSec,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _TestCard extends StatelessWidget {
  final String title;
  final TestDefinition definition;
  final Color color;
  final IconData icon;
  final bool checked;
  final VoidCallback onToggle;

  const _TestCard({
    required this.title,
    required this.definition,
    required this.color,
    required this.icon,
    required this.checked,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: checked ? color.withOpacity(0.07) : AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: checked ? color.withOpacity(0.4) : AppTheme.border,
            width: checked ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.12),
                border: Border.all(color: color.withOpacity(0.25)),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color:
                  checked ? AppTheme.textPri : AppTheme.textSec,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '~${definition.estimatedSeconds}s',
              style: const TextStyle(
                color: AppTheme.textDim,
                fontSize: 11,
              ),
            ),
            const SizedBox(width: 12),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: checked ? color : Colors.transparent,
                border: Border.all(
                  color: checked ? color : AppTheme.border,
                  width: 1.5,
                ),
              ),
              child: checked
                  ? const Icon(Icons.check,
                  color: Colors.black, size: 14)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}