import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rssi_scanner/theme.dart';
import 'package:rssi_scanner/services/websocket_service.dart';
import 'package:rssi_scanner/services/wifi_scanner_service.dart';

class SettingsScreen extends StatefulWidget {
  final WifiScannerService wifi;
  final WebSocketService ws;
  const SettingsScreen({super.key, required this.wifi, required this.ws});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late List<TextEditingController> _bssidControllers;
  bool _showAvailableNetworks = false;

  @override
  void initState() {
    super.initState();
    _bssidControllers = List.generate(4, (i) =>
      TextEditingController(text: widget.wifi.routers[i].bssid),
    );
  }

  @override
  void dispose() {
    for (final c in _bssidControllers) { c.dispose(); }
    super.dispose();
  }

  void _saveSettings() {
    for (int i = 0; i < 4; i++) {
      widget.wifi.setRouterBssid(i, _bssidControllers[i].text);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Router BSSIDs saved!')),
    );
  }

  void _scanAndShow() async {
    final hasPermission = await widget.wifi.requestPermissions();
    if (!hasPermission) return;

    // Trigger a one-time scan
    setState(() => _showAvailableNetworks = true);
    widget.wifi.addListener(_onScanUpdate);

    // Start a quick scan
    widget.wifi.startScanning();
    await Future.delayed(const Duration(seconds: 3));
    widget.wifi.stopScanning();
    widget.wifi.removeListener(_onScanUpdate);
  }

  void _onScanUpdate() { if (mounted) setState(() {}); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionLabel('ROUTER BSSID CONFIGURATION'),
          const SizedBox(height: 8),
          ...List.generate(4, (i) => _buildRouterField(i)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saveSettings,
              icon: const Icon(Icons.save, size: 18),
              label: const Text('SAVE BSSIDS'),
            ),
          ),
          const SizedBox(height: 24),
          _sectionLabel('DISCOVER NEARBY NETWORKS'),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _scanAndShow,
            icon: const Icon(Icons.wifi_find, size: 18),
            label: const Text('SCAN NETWORKS'),
          ),
          if (_showAvailableNetworks) ...[
            const SizedBox(height: 12),
            _buildNetworkList(),
          ],
          const SizedBox(height: 24),
          _sectionLabel('SCAN SETTINGS'),
          const SizedBox(height: 8),
          _buildIntervalSelector(),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(text, style: const TextStyle(
      fontSize: 10, fontWeight: FontWeight.w600,
      letterSpacing: 1, color: AppTheme.textMuted,
    ));
  }

  Widget _buildRouterField(int index) {
    final color = AppTheme.routerColors[index];
    final router = widget.wifi.routers[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
          const SizedBox(width: 8),
          Text(router.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: _bssidControllers[index],
          style: GoogleFonts.jetBrainsMono(fontSize: 12),
          decoration: InputDecoration(
            hintText: 'e.g. aa:bb:cc:dd:ee:ff',
            isDense: true,
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear, size: 16),
              onPressed: () => _bssidControllers[index].clear(),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildNetworkList() {
    final networks = widget.wifi.lastScanResults;
    if (networks.isEmpty) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(20),
        child: Text('Scanning...', style: TextStyle(color: AppTheme.textMuted)),
      ));
    }

    final sorted = List.of(networks)..sort((a, b) => b.level.compareTo(a.level));

    return Container(
      constraints: const BoxConstraints(maxHeight: 300),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: sorted.length.clamp(0, 20),
        separatorBuilder: (context, index) => Divider(height: 1, color: AppTheme.borderSubtle),
        itemBuilder: (_, i) {
          final ap = sorted[i];
          return ListTile(
            dense: true,
            title: Text(ap.ssid.isEmpty ? '(Hidden)' : ap.ssid,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            subtitle: Text(ap.bssid, style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppTheme.textMuted)),
            trailing: Text('${ap.level} dBm', style: GoogleFonts.jetBrainsMono(
              fontSize: 12, color: ap.level > -50 ? AppTheme.success : ap.level > -70 ? AppTheme.warning : AppTheme.danger,
            )),
            onTap: () => _showAssignDialog(ap.bssid, ap.ssid),
          );
        },
      ),
    );
  }

  void _showAssignDialog(String bssid, String ssid) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.bgSecondary,
      title: Text('Assign ${ssid.isEmpty ? bssid : ssid}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('BSSID: $bssid', style: GoogleFonts.jetBrainsMono(fontSize: 11, color: AppTheme.textSecondary)),
        const SizedBox(height: 16),
        const Text('Assign to which router?'),
      ]),
      actions: List.generate(4, (i) => TextButton(
        onPressed: () {
          _bssidControllers[i].text = bssid;
          Navigator.pop(ctx);
        },
        child: Text('Router $i', style: TextStyle(color: AppTheme.routerColors[i])),
      )),
    ));
  }

  Widget _buildIntervalSelector() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Row(children: [
        const Icon(Icons.timer, size: 18, color: AppTheme.textMuted),
        const SizedBox(width: 10),
        const Text('Scan Interval', style: TextStyle(fontSize: 13)),
        const Spacer(),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 1, label: Text('1s')),
            ButtonSegment(value: 2, label: Text('2s')),
            ButtonSegment(value: 3, label: Text('3s')),
          ],
          selected: {widget.wifi.scanInterval.inSeconds},
          onSelectionChanged: (v) {
            widget.wifi.scanInterval = Duration(seconds: v.first);
            setState(() {});
          },
          style: ButtonStyle(
            foregroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected) ? AppTheme.bgPrimary : AppTheme.textSecondary),
            backgroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected) ? AppTheme.accent : Colors.transparent),
          ),
        ),
      ]),
    );
  }
}
