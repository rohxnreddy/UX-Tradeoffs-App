// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'src/core/session_store.dart';
import 'src/core/theme.dart';
import 'src/runner/test_model.dart';
import 'src/services/metadata_service.dart';
import 'src/splash/splash_screen.dart';
import 'src/auth/login_screen.dart';
import 'src/questionnaire/questionnaire_screen.dart';
import 'src/home/home_screen.dart';
import 'src/runner/running_screen.dart';
import 'src/results/results_screen.dart';
import 'src/results/history_screen.dart';
import 'src/services/history_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await SessionStore.instance.init();
  runApp(const UxTradeoffApp());
}

class UxTradeoffApp extends StatelessWidget {
  const UxTradeoffApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Phone Pathology',
      theme: AppTheme.dark,
      home: const _AppRouter(),
    );
  }
}

// ── Router ────────────────────────────────────────────────────────────────────

enum _AppPage { splash, login, questionnaire, home, running, results, history }

class _AppRouter extends StatefulWidget {
  const _AppRouter();

  @override
  State<_AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends State<_AppRouter> {
  _AppPage         _page    = _AppPage.splash;
  List<TestId>     _selected = [];
  List<TestResult> _results  = [];
  bool             _resultsFromHistory = false;

  void _go(_AppPage p) => setState(() => _page = p);

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      transitionBuilder: (child, anim) =>
          FadeTransition(opacity: anim, child: child),
      child: KeyedSubtree(
        key: ValueKey(_page),
        child: _buildPage(),
      ),
    );
  }

  Widget _buildPage() {
    switch (_page) {
      case _AppPage.splash:
        return SplashScreen(onDone: () {
          if (SessionStore.instance.isReady) {
            MetadataService.instance.collectAndSend(includeLocation: true);
            _go(_AppPage.home);
          } else if (SessionStore.instance.isLoggedIn) {
            _go(_AppPage.questionnaire);
          } else {
            _go(_AppPage.login);
          }
        });

      case _AppPage.login:
        return LoginScreen(onLoggedIn: () {
          if (SessionStore.instance.hasAnswered) {
             MetadataService.instance.collectAndSend(includeLocation: true);
             _go(_AppPage.home);
          } else {
             _go(_AppPage.questionnaire);
          }
        });

      case _AppPage.questionnaire:
        return QuestionnaireScreen(onDone: () => _go(_AppPage.home));

      case _AppPage.home:
        return HomeScreen(
          onStart: (selected) {
            setState(() {
              _selected = selected;
              _page     = _AppPage.running;
            });
          },
          onLogout: () async {
            await SessionStore.instance.clear();
            _go(_AppPage.login);
          },
          onShowHistory: () => _go(_AppPage.history),
        );

      case _AppPage.history:
        return HistoryScreen(
          onBack: () => _go(_AppPage.home),
          onSelectRun: (results) {
            setState(() {
              _results = results;
              _resultsFromHistory = true;
              _page = _AppPage.results;
            });
          },
        );

      case _AppPage.running:
        return RunningScreen(
          selectedTests: _selected,
          onDone: (results) async {
            await HistoryService.instance.saveRun(results);
            setState(() {
              _results = results;
              _resultsFromHistory = false;
              _page    = _AppPage.results;
            });
          },
        );

      case _AppPage.results:
        return ResultsScreen(
          results:     _results,
          buttonLabel: _resultsFromHistory ? 'Go Back' : 'Go to Home',
          onBack:      () => _go(_resultsFromHistory ? _AppPage.history : _AppPage.home),
        );
    }
  }
}
