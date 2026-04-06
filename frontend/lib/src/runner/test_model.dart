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
    id:               TestId.vmaf,
    title:            'Video Quality',
    subtitle:         'Video experience assessment',
    iconPath:         'videocam',
    estimatedSeconds: 30,
  ),
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
    id:               TestId.battery,
    title:            'Battery Load',
    subtitle:         'Drain score under stress',
    iconPath:         'battery_charging_full',
    estimatedSeconds: 45,
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

  Map<String, dynamic> toJson() => {
        'id':           id.name,
        'status':       status.name,
        'scores':       scores,
        'errorMessage': errorMessage,
        'completedAt':  completedAt?.toIso8601String(),
      };

  factory TestResult.fromJson(Map<String, dynamic> json) => TestResult(
        id:           TestId.values.byName(json['id']),
        status:       TestStatus.values.byName(json['status']),
        scores:       json['scores'] as Map<String, dynamic>,
        errorMessage: json['errorMessage'],
        completedAt:  json['completedAt'] != null
            ? DateTime.parse(json['completedAt'])
            : null,
      );
}

// ── Test Run (A collection of test results) ───────────────────────────────

class TestRun {
  final String           id;
  final DateTime         timestamp;
  final List<TestResult> results;

  const TestRun({
    required this.id,
    required this.timestamp,
    required this.results,
  });

  int get passCount =>
      results.where((r) => r.status == TestStatus.done).length;

  int get failCount =>
      results.where((r) => r.status == TestStatus.failed).length;

  int get skipCount =>
      results.where((r) => r.status == TestStatus.skipped).length;

  Map<String, dynamic> toJson() => {
        'id':        id,
        'timestamp': timestamp.toIso8601String(),
        'results':   results.map((r) => r.toJson()).toList(),
      };

  factory TestRun.fromJson(Map<String, dynamic> json) => TestRun(
        id:        json['id'],
        timestamp: DateTime.parse(json['timestamp']),
        results:   (json['results'] as List)
            .map((r) => TestResult.fromJson(r))
            .toList(),
      );
}