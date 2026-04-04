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

  // Answers array for the 9 questions
  final List<dynamic> _answers = List.filled(9, null);
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
      key: 'age_group',
      text: 'Age group (choose one)',
      options: [
        _Option('Under 18', Icons.person_outline),
        _Option('18–24', Icons.person_outline),
        _Option('25–34', Icons.person_outline),
        _Option('35–44', Icons.person_outline),
        _Option('45–54', Icons.person_outline),
        _Option('55+', Icons.person_outline),
        _Option('Prefer not to say', Icons.privacy_tip_outlined),
      ],
    ),
    _Question(
      key: 'phone_condition',
      text: 'Is this phone:',
      options: [
        _Option('New (purchased first-hand)', Icons.phone_android),
        _Option('Used (purchased second-hand)', Icons.handshake_outlined),
        _Option('Hand-me-down (from family/friends)', Icons.family_restroom),
      ],
    ),
    _Question(
      key: 'phone_duration',
      text: 'How long have you been using this phone?',
      options: [
        _Option('Less than 6 months', Icons.schedule),
        _Option('6–12 months', Icons.schedule),
        _Option('1–2 years', Icons.schedule),
        _Option('2–3 years', Icons.schedule),
        _Option('More than 3 years', Icons.schedule),
      ],
    ),
    _Question(
      key: 'phone_history',
      text: 'Have you used other phones before this?',
      options: [
        _Option('Yes, mostly new phones', Icons.phone_android),
        _Option('Yes, mostly used/second-hand phones', Icons.handshake_outlined),
        _Option('Yes, a mix', Icons.shuffle),
        _Option('No, this is my first phone', Icons.looks_one_outlined),
      ],
    ),
    _Question(
      key: 'primary_usage',
      text: 'What do you mainly use your phone for? (multi-select)',
      isMultiSelect: true,
      options: [
        _Option('Calls and messaging', Icons.call_outlined),
        _Option('Social media', Icons.group_outlined),
        _Option('Entertainment (videos/music/games)', Icons.play_circle_outline),
        _Option('Work or business', Icons.work_outline),
        _Option('Education/learning', Icons.school_outlined),
        _Option('Accessing government services', Icons.account_balance_outlined),
        _Option('Payments/financial apps', Icons.payment_outlined),
      ],
    ),
    _Question(
      key: 'internet_frequency',
      text: 'How often do you use the internet on your phone?',
      options: [
        _Option('Rarely', Icons.hourglass_empty),
        _Option('A few times a week', Icons.calendar_view_week),
        _Option('Daily', Icons.calendar_today),
        _Option('Almost all the time', Icons.all_inclusive),
      ],
    ),
    _Question(
      key: 'phone_sharing',
      text: 'Is this phone used by:',
      options: [
        _Option('Only me', Icons.person_outline),
        _Option('Shared with family members', Icons.family_restroom),
        _Option('Shared with non-family members', Icons.group_outlined),
      ],
    ),
    _Question(
      key: 'internet_connection_type',
      text: 'What type of internet connection do you mostly use?',
      options: [
        _Option('Mobile data', Icons.cell_tower),
        _Option('Wi-Fi', Icons.wifi),
        _Option('Both equally', Icons.import_export),
        _Option('Rarely use internet', Icons.signal_cellular_off),
      ],
    ),
    _Question(
      key: 'phone_acquisition',
      text: 'How was this phone acquired?',
      options: [
        _Option('Bought by me', Icons.shopping_cart_outlined),
        _Option('Bought by family', Icons.family_restroom),
        _Option('Provided by employer', Icons.work_outline),
        _Option('Received as a gift', Icons.card_giftcard_outlined),
      ],
    ),
  ];

  dynamic _answerFor(int index) {
    if (_questions[index].isMultiSelect) {
      return _answers[index] ?? <String>{};
    }
    return _answers[index];
  }

  void _setAnswer(int index, String value, {bool isMultiSelect = false}) {
    setState(() {
      if (isMultiSelect) {
        Set<String> current = _answers[index] == null ? <String>{} : Set<String>.from(_answers[index]);
        if (current.contains(value)) {
          current.remove(value);
        } else {
          current.add(value);
        }
        _answers[index] = current.isEmpty ? null : current;
      } else {
        _answers[index] = value;
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

    // Persist answers in SessionStore
    await store.setAnswers(
      pAgeGroup:               _answers[0] as String? ?? '',
      pPhoneCondition:         _answers[1] as String? ?? '',
      pPhoneDuration:          _answers[2] as String? ?? '',
      pPhoneHistory:           _answers[3] as String? ?? '',
      pPrimaryUsage:           ((_answers[4] as Set<String>?) ?? {}).join(', '),
      pInternetFrequency:      _answers[5] as String? ?? '',
      pPhoneSharing:           _answers[6] as String? ?? '',
      pInternetConnectionType: _answers[7] as String? ?? '',
      pPhoneAcquisition:       _answers[8] as String? ?? '',
    );

    // Fire metadata collection — sends login + questionnaire + device info
    // to POST /device/metadata and stores the returned session_id.
    MetadataService.instance.collectAndSend(
      testerName: store.googleDisplayName,           // display name from Google Sign-In
      includeLocation: true,                         // Include GPS/Network location
      questionnaireAnswers: {
        'age_group':                  store.ageGroup               ?? '',
        'phone_condition':            store.phoneCondition         ?? '',
        'phone_duration':             store.phoneDuration          ?? '',
        'phone_history':              store.phoneHistory           ?? '',
        'primary_usage':              store.primaryUsage           ?? '',
        'internet_frequency':         store.internetFrequency      ?? '',
        'phone_sharing':              store.phoneSharing           ?? '',
        'internet_connection_type':   store.internetConnectionType ?? '',
        'phone_acquisition':          store.phoneAcquisition       ?? '',
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
    final answer = _answers[_page]; // To check disabled state of Next button
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
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: qi.options.map((opt) {
                        final isSelected = qi.isMultiSelect 
                           ? (ai as Set<String>).contains(opt.label)
                           : ai == opt.label;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _OptionTile(
                            option:   opt,
                            selected: isSelected,
                            onTap:    () => _setAnswer(i, opt.label, isMultiSelect: qi.isMultiSelect),
                          ),
                        );
                      }).toList(),
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
  final bool          isMultiSelect;
  const _Question({required this.key, required this.text, required this.options, this.isMultiSelect = false});
}

class _Option {
  final String   label;
  final IconData icon;
  const _Option(this.label, this.icon);
}