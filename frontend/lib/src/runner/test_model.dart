// lib/src/runner/test_model.dart

enum TestId { vmaf, peaq, pesq, iqa, battery }

class TestDefinition {
  final TestId id;
  final String title;
  final String subtitle;
  final String iconPath;
  final int    estimatedSeconds;

  const TestDefinition({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.iconPath,
    required this.estimatedSeconds,
  });
}

const List<TestDefinition> allTests = [
  TestDefinition(
    id:               TestId.peaq,
    title:            'PEAQ',
    subtitle:         'Audio perceptual quality',
    iconPath:         'music_note',
    estimatedSeconds: 25,
  ),
  TestDefinition(
    id:               TestId.pesq,
    title:            'PESQ',
    subtitle:         'Speech quality via WebRTC',
    iconPath:         'record_voice_over',
    estimatedSeconds: 30,
  ),
  TestDefinition(
    id:               TestId.iqa,
    title:            'IQA',
    subtitle:         'Image quality assessment',
    iconPath:         'image',
    estimatedSeconds: 20,
  ),
  TestDefinition(
    id:               TestId.vmaf,
    title:            'VMAF',
    subtitle:         'Video quality assessment',
    iconPath:         'videocam',
    estimatedSeconds: 30,
  ),
  TestDefinition(
    id:               TestId.battery,
    title:            'Battery Load',
    subtitle:         'Drain score under stress',
    iconPath:         'battery_charging_full',
    estimatedSeconds: 60,
  ),
];

// ── Status / Result ───────────────────────────────────────────────────────────

enum TestStatus { pending, running, done, failed, skipped }

class TestResult {
  final TestId              id;
  final TestStatus          status;
  final Map<String, dynamic> scores;
  final String?             errorMessage;
  final DateTime?           completedAt;

  const TestResult({
    required this.id,
    required this.status,
    this.scores        = const {},
    this.errorMessage,
    this.completedAt,
  });

  TestResult copyWith({
    TestStatus?            status,
    Map<String, dynamic>?  scores,
    String?                errorMessage,
    DateTime?              completedAt,
  }) =>
      TestResult(
        id:           id,
        status:       status       ?? this.status,
        scores:       scores       ?? this.scores,
        errorMessage: errorMessage ?? this.errorMessage,
        completedAt:  completedAt  ?? this.completedAt,
      );
}