// lib/src/results/results_screen.dart
import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../runner/test_model.dart';

class ResultsScreen extends StatefulWidget {
  final List<TestResult> results;
  final VoidCallback onBack;
  final String buttonLabel;

  const ResultsScreen({
    super.key,
    required this.results,
    required this.onBack,
    this.buttonLabel = 'Go to Home',
  });

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen>
    with SingleTickerProviderStateMixin {
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

  static const _testNames = {
    TestId.vmaf: 'Video Experience',
    TestId.peaq: 'Audio Quality',
    TestId.pesq: 'Voice Clarity',
    TestId.iqa: 'Camera Quality',
    TestId.battery: 'Battery Health',
  };

  int get _passCount =>
      widget.results.where((r) => r.status == TestStatus.done).length;

  int get _failCount =>
      widget.results.where((r) => r.status == TestStatus.failed).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: FadeTransition(
        opacity: _fade,
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.good.withOpacity(0.12),
                            border: Border.all(
                                color: AppTheme.good.withOpacity(0.3)),
                          ),
                          child: const Icon(Icons.check_rounded,
                              color: AppTheme.good, size: 22),
                        ),
                        const SizedBox(width: 14),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tests Complete',
                              style: TextStyle(
                                color: AppTheme.textPri,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'All results collected',
                              style: TextStyle(
                                color: AppTheme.textSec,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Summary
                    Row(
                      children: [
                        _SummaryChip(
                          count: _passCount,
                          label: 'Passed',
                          color: AppTheme.good,
                          icon: Icons.check_circle_outline,
                        ),
                        const SizedBox(width: 8),
                        _SummaryChip(
                          count: _failCount,
                          label: 'Failed',
                          color: AppTheme.bad,
                          icon: Icons.error_outline,
                        ),
                        const SizedBox(width: 8),
                        _SummaryChip(
                          count: widget.results
                              .where((r) => r.status == TestStatus.skipped)
                              .length,
                          label: 'Skipped',
                          color: AppTheme.textDim,
                          icon: Icons.remove_circle_outline,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Results list
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: widget.results.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final r = widget.results[i];
                    if (r.status == TestStatus.skipped) {
                      return const SizedBox.shrink();
                    }

                    return _ResultCard(
                      result: r,
                      name: _testNames[r.id]!,
                      color: _testColors[r.id]!,
                      icon: _testIcons[r.id]!,
                    );
                  },
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                child: GestureDetector(
                  onTap: widget.onBack,
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          widget.buttonLabel == 'Go Back'
                              ? Icons.arrow_back_rounded
                              : Icons.home_rounded,
                          color: AppTheme.textSec,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.buttonLabel,
                          style: const TextStyle(
                            color: AppTheme.textSec,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
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
      ),
    );
  }
}

// Summary chip (unchanged)
class _SummaryChip extends StatelessWidget {
  final int count;
  final String label;
  final Color color;
  final IconData icon;

  const _SummaryChip({
    required this.count,
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 13),
        const SizedBox(width: 5),
        Text(
          '$count $label',
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }
}

// Updated Result Card (NO subtitle)
class _ResultCard extends StatelessWidget {
  final TestResult result;
  final String name;
  final Color color;
  final IconData icon;

  const _ResultCard({
    required this.result,
    required this.name,
    required this.color,
    required this.icon,
  });

  String? _getInterpretation(TestId id, dynamic value, {String? key}) {
    if (value == null || value == 'N/A') return null;
    final valStr = value.toString();
    final doubleVal = double.tryParse(valStr);
    if (doubleVal == null) return null;

    if (id == TestId.vmaf) {
      if (doubleVal >= 93) return 'Excellent';
      if (doubleVal >= 80) return 'Good';
      if (doubleVal >= 60) return 'Fair';
      if (doubleVal >= 40) return 'Poor';
      return 'Bad';
    } else if (id == TestId.iqa) {
      final metric = key?.toLowerCase() ?? '';
      // No-reference metrics: lower is better
      if (metric == 'brisque' || metric == 'niqe' || metric == 'piqe') {
        final thresholds = {
          'brisque': [20.0, 40.0, 60.0, 80.0],
          'niqe': [3.5, 5.5, 7.5, 10.0],
          'piqe': [25.0, 45.0, 60.0, 80.0],
        }[metric]!;
        if (doubleVal <= thresholds[0]) return 'Excellent';
        if (doubleVal <= thresholds[1]) return 'Good';
        if (doubleVal <= thresholds[2]) return 'Fair';
        if (doubleVal <= thresholds[3]) return 'Poor';
        return 'Bad';
      }
      // Camera Score / CDI: higher is better
      if (metric.contains('score')) {
        if (doubleVal >= 85) return 'Excellent';
        if (doubleVal >= 70) return 'Good';
        if (doubleVal >= 55) return 'Fair';
        if (doubleVal >= 40) return 'Poor';
        return 'Bad';
      }
    } else if (id == TestId.peaq) {
      if (doubleVal >= -0.5) return 'Imperceptible degradation';
      if (doubleVal >= -1.0) return 'Perceptible but not annoying';
      if (doubleVal >= -2.0) return 'Slightly annoying';
      if (doubleVal >= -3.0) return 'Annoying';
      return 'Very annoying degradation';
    } else if (id == TestId.pesq) {
      if (doubleVal >= 4.0) return 'Excellent quality';
      if (doubleVal >= 3.0) return 'Good quality';
      if (doubleVal >= 2.0) return 'Poor quality';
      return 'Very poor quality';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isOk = result.status == TestStatus.done;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOk ? color.withOpacity(0.3) : AppTheme.bad.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withOpacity(0.12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    color: AppTheme.textPri,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(
                isOk ? Icons.check_circle : Icons.error_outline,
                color: isOk ? AppTheme.good : AppTheme.bad,
                size: 20,
              ),
            ],
          ),

          if (isOk && result.scores.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color.withOpacity(0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withOpacity(0.12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: result.scores.entries.map((e) {
                  final interp = _getInterpretation(result.id, e.value, key: e.key);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            e.key,
                            style: const TextStyle(
                              color: AppTheme.textSec,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          flex: 2,
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: e.value.toString(),
                                  style: TextStyle(
                                    color: color,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (interp != null)
                                  TextSpan(
                                    text: '  $interp',
                                    style: TextStyle(
                                      color: color.withOpacity(0.8),
                                      fontSize: 11,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                              ],
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],

          if (!isOk && result.errorMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.bad.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.bad.withOpacity(0.2)),
              ),
              child: Text(
                result.errorMessage!,
                style: const TextStyle(
                  color: AppTheme.bad,
                  fontSize: 12,
                ),
              ),
            ),
          ],

          if (result.completedAt != null) ...[
            const SizedBox(height: 10),
            Text(
              'Completed at ${_fmt(result.completedAt!)}',
              style: const TextStyle(color: AppTheme.textDim, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
}
