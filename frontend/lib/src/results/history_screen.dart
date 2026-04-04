// lib/src/results/history_screen.dart
import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../runner/test_model.dart';
import '../services/history_service.dart';

class HistoryScreen extends StatefulWidget {
  final Function(List<TestResult>) onSelectRun;
  final VoidCallback onBack;

  const HistoryScreen({
    super.key,
    required this.onSelectRun,
    required this.onBack,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<TestRun>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture = HistoryService.instance.getHistory();
  }

  static const _testIcons = {
    TestId.vmaf: Icons.videocam_outlined,
    TestId.peaq: Icons.music_note_outlined,
    TestId.pesq: Icons.record_voice_over_outlined,
    TestId.iqa: Icons.image_outlined,
    TestId.battery: Icons.battery_charging_full_outlined,
  };

  static const _testColors = {
    TestId.vmaf: AppTheme.vmafColor,
    TestId.peaq: AppTheme.peaqColor,
    TestId.pesq: AppTheme.pesqColor,
    TestId.iqa: AppTheme.iqaColor,
    TestId.battery: AppTheme.battColor,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: AppTheme.textPri, size: 20),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Test History',
                    style: TextStyle(
                      color: AppTheme.textPri,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () async {
                      await HistoryService.instance.clear();
                      setState(() {
                         _historyFuture = HistoryService.instance.getHistory();
                      });
                    },
                    icon: const Icon(Icons.delete_sweep_outlined,
                        color: AppTheme.textDim, size: 22),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            Expanded(
              child: FutureBuilder<List<TestRun>>(
                future: _historyFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final history = snapshot.data ?? [];

                  if (history.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.history_toggle_off_rounded,
                              size: 64, color: AppTheme.textDim.withOpacity(0.3)),
                          const SizedBox(height: 16),
                          const Text(
                            'No tests run yet',
                            style: TextStyle(color: AppTheme.textDim, fontSize: 16),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    itemCount: history.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 14),
                    itemBuilder: (context, index) {
                      final run = history[index];
                      return _HistoryCard(
                        run: run,
                        onTap: () => widget.onSelectRun(run.results),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final TestRun run;
  final VoidCallback onTap;

  const _HistoryCard({required this.run, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final timeStr = _formatTimestamp(run.timestamp);
    final total = run.results.where((r) => r.status != TestStatus.skipped).length;
    final passed = run.passCount;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      timeStr,
                      style: const TextStyle(
                        color: AppTheme.textPri,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$passed/$total tests passed',
                      style: TextStyle(
                        color: passed == total ? AppTheme.good : AppTheme.warn,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                const Icon(Icons.chevron_right_rounded,
                    color: AppTheme.textDim, size: 24),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: run.results
                  .where((r) => r.status != TestStatus.skipped)
                  .map((r) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _HistoryScreenState._testColors[r.id]!
                                .withOpacity(0.15),
                          ),
                          child: Icon(
                            _HistoryScreenState._testIcons[r.id],
                            color: _HistoryScreenState._testColors[r.id],
                            size: 16,
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
