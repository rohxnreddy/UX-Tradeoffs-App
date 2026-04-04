// lib/src/questionnaire/questionnaire_screen.dart
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../core/session_store.dart';
import '../core/theme.dart';
import '../services/metadata_service.dart';

class QuestionnaireScreen extends StatefulWidget {
  final VoidCallback onDone;
  const QuestionnaireScreen({super.key, required this.onDone});

  @override
  State<QuestionnaireScreen> createState() => _QuestionnaireScreenState();
}

class _QuestionnaireScreenState extends State<QuestionnaireScreen> {
  final PageController _pageCtrl = PageController();
  int _page = 0;
  bool _submitting = false;

  // Answers — stored using the exact DB column names as keys
  String? _usage;      // → device_usage
  String? _network;    // → network_env
  String? _purpose;    // → testing_purpose
  String? _frequency;  // → usage_frequency
  bool _locationPrompted = false;

  @override
  void initState() {
    super.initState();
    _requestLocationPermission();
  }

  Future<void> _requestLocationPermission() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      setState(() => _locationPrompted = true);
    } catch (_) {}
  }

  static const _questions = [
    _Question(
      key: 'device_usage',
      text: 'How do you primarily use your phone?',
      options: [
        _Option('Media & streaming',      Icons.play_circle_outline),
        _Option('Calls & communication',  Icons.call_outlined),
        _Option('Work & productivity',    Icons.work_outline),
        _Option('Gaming & entertainment', Icons.games_outlined),
      ],
    ),
    _Question(
      key: 'network_env',
      text: 'What\'s your typical network environment?',
      options: [
        _Option('Strong Wi-Fi (home/office)', Icons.wifi),
        _Option('Moderate Wi-Fi',             Icons.wifi_2_bar),
        _Option('4G / LTE cellular',          Icons.signal_cellular_alt),
        _Option('Varies / mixed',             Icons.shuffle),
      ],
    ),
    _Question(
      key: 'testing_purpose',
      text: 'What\'s the main purpose of this test?',
      options: [
        _Option('Personal research',    Icons.person_outline),
        _Option('Academic study',       Icons.school_outlined),
        _Option('Product benchmarking', Icons.analytics_outlined),
        _Option('QA / field testing',   Icons.checklist_outlined),
      ],
    ),
    _Question(
      key: 'usage_frequency',
      text: 'How often do you run quality tests?',
      options: [
        _Option('First time',    Icons.new_releases_outlined),
        _Option('Occasionally',  Icons.hourglass_empty),
        _Option('Weekly',        Icons.calendar_today_outlined),
        _Option('Daily / often', Icons.repeat),
      ],
    ),
  ];

  String? _answerFor(int index) {
    switch (index) {
      case 0: return _usage;
      case 1: return _network;
      case 2: return _purpose;
      case 3: return _frequency;
      default: return null;
    }
  }

  void _setAnswer(int index, String value) {
    setState(() {
      switch (index) {
        case 0: _usage     = value; break;
        case 1: _network   = value; break;
        case 2: _purpose   = value; break;
        case 3: _frequency = value; break;
      }
    });
  }

  Future<void> _next() async {
    if (_page < _questions.length - 1) {
      await _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
      setState(() => _page++);
    } else {
      await _submit();
    }
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);

    final store = SessionStore.instance;

    // Persist answers in SessionStore (keys match DB column names)
    store.setAnswers(
      usage:     _usage     ?? '',
      network:   _network   ?? '',
      purpose:   _purpose   ?? '',
      frequency: _frequency ?? '',
    );

    // Fire metadata collection — sends login + questionnaire + device info
    // to POST /device/metadata and stores the returned session_id.
    // This runs in the background; onDone() is called immediately so the
    // user is not blocked waiting for the network round-trip.
    MetadataService.instance.collectAndSend(
      testerName: store.googleDisplayName,           // display name from Google Sign-In
      includeLocation: true,                         // Include GPS/Network location
      questionnaireAnswers: {
        'device_usage':    store.deviceUsage    ?? '',
        'network_env':     store.networkEnv     ?? '',
        'testing_purpose': store.testingPurpose ?? '',
        'usage_frequency': store.usageFrequency ?? '',
      },
    );

    widget.onDone();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q      = _questions[_page];
    final answer = _answerFor(_page);
    final isLast = _page == _questions.length - 1;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Progress bar
            _ProgressBar(current: _page + 1, total: _questions.length),

            const SizedBox(height: 24),

            // Question text
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Question ${_page + 1} of ${_questions.length}',
                    style: const TextStyle(
                      color: AppTheme.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      q.text,
                      key: ValueKey(_page),
                      style: const TextStyle(
                        color: AppTheme.textPri,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Options — paged (physics locked; navigation is button-driven only)
            Expanded(
              child: PageView(
                controller: _pageCtrl,
                physics: const NeverScrollableScrollPhysics(),
                children: List.generate(_questions.length, (i) {
                  final qi = _questions[i];
                  final ai = _answerFor(i);
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: qi.options.map((opt) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _OptionTile(
                          option:   opt,
                          selected: ai == opt.label,
                          onTap:    () => _setAnswer(i, opt.label),
                        ),
                      )).toList(),
                    ),
                  );
                }),
              ),
            ),

            // Next / Start Testing button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              child: AnimatedOpacity(
                opacity: answer != null ? 1.0 : 0.3,
                duration: const Duration(milliseconds: 200),
                child: GestureDetector(
                  onTap: (answer != null && !_submitting) ? _next : null,
                  child: Container(
                    width: double.infinity,
                    height: 54,
                    decoration: BoxDecoration(
                      color: AppTheme.accent,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.accent.withOpacity(0.25),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Center(
                      child: _submitting
                          ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                          : Text(
                        isLast ? 'Start Testing' : 'Next',
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _ProgressBar extends StatelessWidget {
  final int current;
  final int total;
  const _ProgressBar({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Quick Setup',
                  style: TextStyle(color: AppTheme.textSec, fontSize: 13)),
              Text('$current / $total',
                  style: const TextStyle(color: AppTheme.textDim, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: current / total,
              backgroundColor: AppTheme.surface2,
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accent),
              minHeight: 3,
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final _Option option;
  final bool selected;
  final VoidCallback onTap;
  const _OptionTile({required this.option, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: selected ? AppTheme.accent.withOpacity(0.12) : AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppTheme.accent : AppTheme.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              option.icon,
              color: selected ? AppTheme.accent : AppTheme.textSec,
              size: 22,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                option.label,
                style: TextStyle(
                  color: selected ? AppTheme.textPri : AppTheme.textSec,
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, color: AppTheme.accent, size: 18),
          ],
        ),
      ),
    );
  }
}

// ── Data classes ──────────────────────────────────────────────────────────────

class _Question {
  final String        key;
  final String        text;
  final List<_Option> options;
  const _Question({required this.key, required this.text, required this.options});
}

class _Option {
  final String   label;
  final IconData icon;
  const _Option(this.label, this.icon);
}