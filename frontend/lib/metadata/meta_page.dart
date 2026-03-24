import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:frontend/metadata/metadata.dart';

class MetaPage extends StatefulWidget {
  const MetaPage({super.key});

  @override
  State<MetaPage> createState() => _MetaPageState();
}

class _MetaPageState extends State<MetaPage> {
  DeviceMeta? _meta;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final meta = await MetaCollector.instance.collect(includeLocation: true);
      setState(() {
        _meta = meta;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _copyJson() {
    if (_meta == null) return;
    final pretty =
    const JsonEncoder.withIndent('  ').convert(_meta!.toJson());
    Clipboard.setData(ClipboardData(text: pretty));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('JSON copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Collecting metadata…'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final m = _meta!;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _copyJson,
        icon: const Icon(Icons.copy),
        label: const Text('Copy JSON'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            _Section(
              icon: Icons.phone_android,
              title: 'Device Hardware',
              color: Colors.indigo,
              items: {
                'Model': m.deviceModel,
                'Brand': m.deviceBrand,
                'Manufacturer': m.deviceManufacturer,
                'Product': m.deviceProduct,
                'Hardware': m.deviceHardware,
                'Supported ABIs': m.supportedAbis,
                'CPU Cores': m.cpuCores?.toString(),
              },
            ),
            _Section(
              icon: Icons.settings_outlined,
              title: 'OS & System',
              color: Colors.teal,
              items: {
                'Android Version': m.androidVersion,
                'SDK Version': m.sdkVersion?.toString(),
                'Build Number': m.buildNumber,
                'Security Patch': m.securityPatchLevel,
                'Bootloader': m.bootloader,
                'Build Fingerprint': m.buildFingerprint,
                'Physical Device': m.isPhysicalDevice?.toString(),
                'Rooted': m.isRooted?.toString(),
              },
            ),
            _Section(
              icon: Icons.apps_outlined,
              title: 'App Info',
              color: Colors.orange,
              items: {
                'Package Name': m.appPackageName,
                'Version': m.appVersionName,
                'Version Code': m.appVersionCode?.toString(),
                'Installer': m.appInstallerPackage,
                'Debug Build': m.isDebugBuild?.toString(),
              },
            ),
            // [2] Performance metrics
            _Section(
              icon: Icons.speed_outlined,
              title: 'Performance',
              color: Colors.deepOrange,
              items: {
                'Launch Time':
                m.appLaunchTimeMs != null ? '${m.appLaunchTimeMs} ms' : null,
                'Frame Drops': m.frameDropCount?.toString(),
                'Last Crash': m.lastCrashInfo ?? 'None',
              },
            ),
            _Section(
              icon: Icons.battery_charging_full_outlined,
              title: 'Battery',
              color: Colors.green,
              items: {
                'Level': m.batteryLevel != null ? '${m.batteryLevel}%' : null,
                'State': m.batteryState,
              },
            ),
            // [3] Network quality
            _Section(
              icon: Icons.wifi_outlined,
              title: 'Network',
              color: Colors.blue,
              items: {
                'Connection Type': m.connectionType,
                'Speed Category': m.networkSpeedCategory,
                'Latency': m.networkLatencyMs != null
                    ? '${m.networkLatencyMs} ms'
                    : null,
                'WiFi Name (SSID)': m.wifiName,
                'WiFi BSSID': m.wifiBSSID,
                'Local IPv4': m.localIpv4,
                'Local IPv6': m.localIpv6,
                'VPN Active': m.isVpnActive?.toString(),
              },
            ),
            _Section(
              icon: Icons.location_on_outlined,
              title: 'Location',
              color: Colors.red,
              items: {
                'Latitude': m.latitude?.toStringAsFixed(6),
                'Longitude': m.longitude?.toStringAsFixed(6),
                'Altitude': m.altitude != null
                    ? '${m.altitude!.toStringAsFixed(1)} m'
                    : null,
                'Accuracy': m.locationAccuracy != null
                    ? '±${m.locationAccuracy!.toStringAsFixed(1)} m'
                    : null,
                'Speed': m.speed != null
                    ? '${m.speed!.toStringAsFixed(1)} m/s'
                    : null,
                'Bearing': m.bearing != null
                    ? '${m.bearing!.toStringAsFixed(1)}°'
                    : null,
                'City': m.locality,
                'State / Region': m.adminArea,
                'Country': m.country,
                'ISO Country Code': m.isoCountryCode,
                'Postal Code': m.postalCode,
              },
            ),
            _Section(
              icon: Icons.language_outlined,
              title: 'Locale & Regional',
              color: Colors.purple,
              items: {
                'Language': m.deviceLanguage,
                'Locale': m.deviceLocale,
                'Timezone': m.timezone,
                'Country Code': m.countryCode,
              },
            ),
            // [4][5][6] Device tier, RAM, disk
            _Section(
              icon: Icons.memory_outlined,
              title: 'Memory & Storage',
              color: Colors.cyan.shade700,
              items: {
                'Device Tier': m.deviceTier,
                'Total RAM': m.totalRamMb != null ? '${m.totalRamMb} MB' : null,
                'Available RAM':
                m.availableRamMb != null ? '${m.availableRamMb} MB' : null,
                'Total Disk': m.totalDiskMb != null
                    ? '${(m.totalDiskMb! / 1024).toStringAsFixed(1)} GB'
                    : null,
                'Free Disk': m.freeDiskMb != null
                    ? '${(m.freeDiskMb! / 1024).toStringAsFixed(1)} GB'
                    : null,
              },
            ),
            // [7] Display refresh rate
            _Section(
              icon: Icons.monitor_outlined,
              title: 'Display',
              color: Colors.pink,
              items: {
                'Width (px)': m.screenWidthPx?.toStringAsFixed(0),
                'Height (px)': m.screenHeightPx?.toStringAsFixed(0),
                'Density (dpr)': m.screenDensity?.toStringAsFixed(2),
                'Refresh Rate': m.displayRefreshRate != null
                    ? '${m.displayRefreshRate!.toStringAsFixed(0)} Hz'
                    : null,
              },
            ),
            // [8] Audio output route
            _Section(
              icon: Icons.headphones_outlined,
              title: 'Audio',
              color: Colors.deepPurple,
              items: {
                'Output Route': m.audioOutputRoute,
              },
            ),
            _Section(
              icon: Icons.lock_outline,
              title: 'Permissions',
              color: Colors.brown,
              items: m.permissionStatuses?.map(
                    (k, v) => MapEntry(
                  k.replaceAll('Permission.', ''),
                  v,
                ),
              ) ??
                  {},
            ),
            // [1][9] User behavior & lifecycle
            _Section(
              icon: Icons.access_time_outlined,
              title: 'Session',
              color: Colors.blueGrey,
              items: {
                'Session Start': m.sessionStart?.toLocal().toString(),
                'Screen Views': m.sessionScreenViews?.toString(),
                'User Actions': m.sessionUserActions?.toString(),
                'Times Backgrounded': m.sessionBackgroundCount?.toString(),
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section card widget
// ─────────────────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final Map<String, String?> items;

  const _Section({
    required this.icon,
    required this.title,
    required this.color,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final visibleItems =
    items.entries.where((e) => e.value != null && e.value!.isNotEmpty).toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius:
              const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: color,
                  ),
                ),
                const Spacer(),
                Text(
                  '${visibleItems.length} fields',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          // Rows
          if (visibleItems.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No data available (permission may be required)',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            )
          else
            ...visibleItems.asMap().entries.map((entry) {
              final isLast = entry.key == visibleItems.length - 1;
              return _Row(
                label: entry.value.key,
                value: entry.value.value!,
                isLast: isLast,
              );
            }),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool isLast;

  const _Row({
    required this.label,
    required this.value,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 140,
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: Colors.grey.shade100,
          ),
      ],
    );
  }
}