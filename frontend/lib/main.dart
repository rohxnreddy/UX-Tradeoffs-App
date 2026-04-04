import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:frontend/vmaf/vmaf_home.dart';
import 'package:frontend/peaq/peaq_test.dart';
import 'package:frontend/pesq/pesq_test.dart';
import 'package:frontend/IQA/IQA.dart';
import 'package:frontend/battery/battery_load_page.dart';
import 'package:frontend/home/metric_runner_home.dart';
import 'package:frontend/metadata/meta_page.dart';
import 'metadata/metadata.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SchedulerBinding.instance.addPostFrameCallback((_) {
    PerformanceTracker.instance.markFirstFrame();
  });
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'UX Trade Off App',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const HomeNav(),
    );
  }
}

class HomeNav extends StatefulWidget {
  const HomeNav({super.key});

  @override
  State<HomeNav> createState() => _HomeNavState();
}

class _HomeNavState extends State<HomeNav> {
  int _selectedIndex = 0; // 👈 Meta page opens first
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  void _onItemSelected(int index) {
    setState(() => _selectedIndex = index);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          // ── 0 · Home Runner ──────────────────────────────────────
          _buildPageScaffold(
            title: 'Run Metric Tests',
            icon: Icons.play_circle_outline,
            body: const MetricRunnerHome(),
          ),
          // ── 1 · Meta ─────────────────────────────────────────────
          _buildPageScaffold(
            title: 'Device Meta',
            icon: Icons.phone_android_outlined,
            body: const MetaPage(),
          ),
          // ── 2 · VMAF ─────────────────────────────────────────────
          VmafHome(onMenuPressed: () => _scaffoldKey.currentState?.openDrawer()),
          // ── 3 · PEAQ ─────────────────────────────────────────────
          _buildPageScaffold(
            title: 'PEAQ — Audio Quality',
            icon: Icons.music_note_outlined,
            body: const PeaqTestScreen(),
          ),
          // ── 4 · PESQ ─────────────────────────────────────────────
          _buildPageScaffold(
            title: 'PESQ — Speech Quality',
            icon: Icons.record_voice_over_outlined,
            body: const PesqTestScreen(),
          ),
          // ── 5 · IQA ──────────────────────────────────────────────
          _buildPageScaffold(
            title: 'IQA — Image Quality',
            icon: Icons.image_outlined,
            body: const IQAPage(),
          ),
          // ── 6 · Battery Load ─────────────────────────────────────
          _buildPageScaffold(
            title: 'Battery Load Tester',
            icon: Icons.battery_charging_full_outlined,
            body: const BatteryLoadPage(),
          ),
        ],
      ),
    );
  }

  Widget _buildPageScaffold({
    required String title,
    required IconData icon,
    required Widget body,
  }) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        elevation: 1,
      ),
      body: body,
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: const [
                Icon(Icons.analytics_outlined, color: Colors.white, size: 40),
                SizedBox(height: 12),
                Text(
                  'UX Tradeoffs',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Quality Testing Suite',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
          _buildDrawerItem(
            icon: Icons.play_circle_outline,
            title: 'Run Metric Tests',
            subtitle: 'Automated Sequential Runner',
            index: 0,
          ),
          _buildDrawerItem(
            icon: Icons.phone_android_outlined,
            title: 'Device Meta',
            subtitle: 'Device & User Metadata',
            index: 1,
          ),
          _buildDrawerItem(
            icon: Icons.videocam_outlined,
            title: 'VMAF',
            subtitle: 'Video Quality Assessment',
            index: 2,
          ),
          _buildDrawerItem(
            icon: Icons.music_note_outlined,
            title: 'PEAQ',
            subtitle: 'Audio Quality Assessment',
            index: 3,
          ),
          _buildDrawerItem(
            icon: Icons.record_voice_over_outlined,
            title: 'PESQ',
            subtitle: 'Speech Quality Assessment',
            index: 4,
          ),
          _buildDrawerItem(
            icon: Icons.image_outlined,
            title: 'IQA',
            subtitle: 'Image Quality Assessment',
            index: 5,
          ),
          _buildDrawerItem(
            icon: Icons.battery_charging_full_outlined,
            title: 'Battery Load',
            subtitle: 'Battery Stress Testing',
            index: 6,
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required int index,
  }) {
    final isSelected = _selectedIndex == index;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? Colors.blue.shade50 : null,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: isSelected ? Colors.blue : Colors.grey.shade700,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.blue : Colors.black87,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: isSelected ? Colors.blue.shade300 : Colors.grey,
          ),
        ),
        selected: isSelected,
        onTap: () => _onItemSelected(index),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}