import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rssi_scanner/theme.dart';
import 'package:rssi_scanner/services/websocket_service.dart';
import 'package:rssi_scanner/services/wifi_scanner_service.dart';
import 'package:rssi_scanner/screens/settings_screen.dart';
import 'package:rssi_scanner/screens/data_collection_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final WebSocketService _ws = WebSocketService();
  final WifiScannerService _wifi = WifiScannerService();
  final TextEditingController _urlController = TextEditingController();
  Timer? _sendTimer;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _urlController.text = _ws.serverUrl;
    _ws.addListener(_onUpdate);
    _wifi.addListener(_onUpdate);
    _pulseController = AnimationController(
      vsync: this, duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _wifi.requestPermissions();
  }

  void _onUpdate() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    _sendTimer?.cancel();
    _ws.removeListener(_onUpdate);
    _wifi.removeListener(_onUpdate);
    _ws.dispose();
    _wifi.dispose();
    _pulseController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _toggleConnection() {
    if (_ws.isConnected) {
      _sendTimer?.cancel();
      _ws.disconnect();
      _wifi.stopScanning();
    } else {
      _ws.serverUrl = _urlController.text.trim();
      _ws.connect().then((_) {
        if (_ws.isConnected && _wifi.hasAllBssids) {
          _wifi.startScanning();
          _sendTimer = Timer.periodic(
            _wifi.scanInterval,
            (_) => _ws.sendRssi(_wifi.getCurrentRssi()),
          );
        }
      });
    }
  }

  void _startScanning() {
    if (!_wifi.hasAllBssids) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Configure all 4 router BSSIDs in Settings first'),
      ));
      return;
    }
    _wifi.startScanning();
    _sendTimer?.cancel();
    _sendTimer = Timer.periodic(
      _wifi.scanInterval, (_) => _ws.sendRssi(_wifi.getCurrentRssi()),
    );
  }

  void _stopScanning() {
    _sendTimer?.cancel();
    _wifi.stopScanning();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            _buildAppBar(),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _buildConnectionCard(),
                  const SizedBox(height: 16),
                  _buildPositionCard(),
                  const SizedBox(height: 16),
                  _buildRssiCards(),
                  const SizedBox(height: 16),
                  _buildDataCollectionCard(),
                  const SizedBox(height: 16),
                  _buildStatsCard(),
                  const SizedBox(height: 80),
                ]),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _ws.isConnected
          ? FloatingActionButton.extended(
              onPressed: _wifi.isScanning ? _stopScanning : _startScanning,
              icon: Icon(_wifi.isScanning ? Icons.stop : Icons.play_arrow),
              label: Text(_wifi.isScanning ? 'Stop' : 'Scan'),
              backgroundColor: _wifi.isScanning ? AppTheme.danger : AppTheme.accent,
              foregroundColor: AppTheme.bgPrimary,
            )
          : null,
    );
  }

  SliverAppBar _buildAppBar() {
    return SliverAppBar(
      floating: true,
      title: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
          ),
          child: const Icon(Icons.wifi_find, size: 18, color: AppTheme.accent),
        ),
        const SizedBox(width: 10),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [AppTheme.accent, AppTheme.accentBlue],
          ).createShader(bounds),
          child: Text('RSSI Scanner', style: GoogleFonts.inter(
            fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white,
          )),
        ),
      ]),
      actions: [
        IconButton(
          icon: const Icon(Icons.grid_view_rounded, color: AppTheme.accent),
          tooltip: 'Data Collection',
          onPressed: () {
            Navigator.push(context,
              MaterialPageRoute(builder: (_) => DataCollectionScreen(
                wifiScanner: _wifi,
                serverBaseUrl: _ws.serverUrl.replaceAll('/ws/mobile', '').replaceAll('ws://', 'http://'),
              )),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined, color: AppTheme.textSecondary),
          onPressed: () async {
            await Navigator.push(context,
              MaterialPageRoute(builder: (_) => SettingsScreen(wifi: _wifi, ws: _ws)),
            );
            setState(() {});
          },
        ),
      ],
    );
  }

  Widget _buildConnectionCard() {
    final stateColor = switch (_ws.state) {
      WsConnectionState.connected => AppTheme.success,
      WsConnectionState.connecting => AppTheme.warning,
      WsConnectionState.error => AppTheme.danger,
      _ => AppTheme.textMuted,
    };
    final stateText = switch (_ws.state) {
      WsConnectionState.connected => 'Connected',
      WsConnectionState.connecting => 'Connecting...',
      WsConnectionState.error => 'Error',
      _ => 'Disconnected',
    };

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: stateColor.withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(
            shape: BoxShape.circle, color: stateColor,
            boxShadow: [BoxShadow(color: stateColor.withValues(alpha: 0.5), blurRadius: 8)],
          )),
          const SizedBox(width: 10),
          Text(stateText, style: TextStyle(color: stateColor, fontSize: 13, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('SERVER', style: TextStyle(color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1)),
        ]),
        const SizedBox(height: 14),
        TextField(
          controller: _urlController,
          style: GoogleFonts.jetBrainsMono(fontSize: 12, color: AppTheme.textPrimary),
          decoration: const InputDecoration(
            hintText: 'ws://host:6060/ws/mobile',
            prefixIcon: Icon(Icons.link, size: 18, color: AppTheme.textMuted),
            isDense: true,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: _ws.isConnected
              ? OutlinedButton.icon(
                  onPressed: _toggleConnection,
                  icon: const Icon(Icons.link_off, size: 18),
                  label: const Text('DISCONNECT'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.danger,
                    side: BorderSide(color: AppTheme.danger.withValues(alpha: 0.3)),
                  ),
                )
              : ElevatedButton.icon(
                  onPressed: _toggleConnection,
                  icon: const Icon(Icons.power, size: 18),
                  label: const Text('CONNECT'),
                ),
        ),
        if (_ws.errorMessage != null) ...[
          const SizedBox(height: 10),
          Text(_ws.errorMessage!, style: const TextStyle(color: AppTheme.danger, fontSize: 11)),
        ],
      ]),
    );
  }

  Widget _buildPositionCard() {
    final pos = _ws.lastPosition;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.15)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.my_location, size: 16, color: AppTheme.accent),
          const SizedBox(width: 8),
          const Text('ESTIMATED POSITION', style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppTheme.textMuted,
          )),
        ]),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _coordBox('X', pos?.x ?? 0, AppTheme.accent),
          _coordBox('Y', pos?.y ?? 0, AppTheme.accentBlue),
          _coordBox('Z', pos?.z ?? 0, AppTheme.accentPurple),
        ]),
        if (pos != null) ...[
          const SizedBox(height: 16),
          _buildMiniMap(pos),
        ],
      ]),
    );
  }

  Widget _coordBox(String label, double value, Color color) {
    return Column(children: [
      Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color.withValues(alpha: 0.7), letterSpacing: 1)),
      const SizedBox(height: 4),
      Text(value.toStringAsFixed(2), style: GoogleFonts.jetBrainsMono(fontSize: 28, fontWeight: FontWeight.w500, color: color)),
      const Text('meters', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
    ]);
  }

  Widget _buildMiniMap(PositionData pos) {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: AppTheme.bgPrimary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: LayoutBuilder(builder: (ctx, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        const pad = 20.0;
        final mapW = w - pad * 2;
        final mapH = h - pad * 2;
        final dotX = pad + (pos.x / 3.2).clamp(0.0, 1.0) * mapW;
        final dotY = pad + (1 - pos.y / 3.0).clamp(0.0, 1.0) * mapH;

        return Stack(children: [
          Positioned(left: pad, top: pad, width: mapW, height: mapH,
            child: Container(decoration: BoxDecoration(
              border: Border.all(color: AppTheme.accent.withValues(alpha: 0.2)),
              borderRadius: BorderRadius.circular(4),
            )),
          ),
          for (int i = 0; i < 4; i++)
            Positioned(
              left: pad + [0.0, 1.0, 0.0, 1.0][i] * mapW - 6,
              top: pad + [1.0, 1.0, 0.0, 0.0][i] * mapH - 6,
              child: Container(width: 12, height: 12, decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.routerColors[i].withValues(alpha: 0.8),
                border: Border.all(color: AppTheme.routerColors[i], width: 1.5),
              )),
            ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOut,
            left: dotX - 8, top: dotY - 8,
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (_, child) => Container(
                width: 16, height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle, color: AppTheme.accent,
                  boxShadow: [BoxShadow(
                    color: AppTheme.accent.withValues(alpha: 0.3 + _pulseController.value * 0.3),
                    blurRadius: 8 + _pulseController.value * 8,
                  )],
                ),
              ),
            ),
          ),
          Positioned(left: pad + 4, bottom: pad + 4,
            child: const Text('(0,0)', style: TextStyle(fontSize: 9, color: AppTheme.textMuted))),
          Positioned(right: pad + 4, top: pad + 4,
            child: const Text('(3.2,3.0)', style: TextStyle(fontSize: 9, color: AppTheme.textMuted))),
        ]);
      }),
    );
  }

  Widget _buildRssiCards() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('RSSI READINGS', style: TextStyle(
        fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppTheme.textMuted,
      )),
      const SizedBox(height: 10),
      ...List.generate(4, (i) {
        final router = _wifi.routers[i];
        final rssi = router.lastRssi;
        final strength = ((rssi + 100) / 60).clamp(0.0, 1.0);
        final color = AppTheme.routerColors[i];
        final configured = router.bssid.isNotEmpty;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.bgCard, borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.15)),
          ),
          child: Row(children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(router.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: strength,
                  backgroundColor: color.withValues(alpha: 0.1),
                  valueColor: AlwaysStoppedAnimation(color),
                  minHeight: 4,
                ),
              ),
            ])),
            const SizedBox(width: 12),
            Text(
              configured ? '${rssi.toStringAsFixed(0)} dBm' : 'N/A',
              style: GoogleFonts.jetBrainsMono(fontSize: 14, fontWeight: FontWeight.w500, color: configured ? color : AppTheme.textMuted),
            ),
          ]),
        );
      }),
    ]);
  }

  Widget _buildDataCollectionCard() {
    return GestureDetector(
      onTap: () {
        Navigator.push(context,
          MaterialPageRoute(builder: (_) => DataCollectionScreen(
            wifiScanner: _wifi,
            serverBaseUrl: _ws.serverUrl
                .replaceAll('/ws/mobile', '')
                .replaceAll('ws://', 'http://'),
          )),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.accent.withValues(alpha: 0.08),
              AppTheme.accentBlue.withValues(alpha: 0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.accent.withValues(alpha: 0.2)),
        ),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.grid_view_rounded, color: AppTheme.accent, size: 22),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Data Collection', style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary,
              )),
              SizedBox(height: 3),
              Text('Collect RSSI fingerprints for each grid cell', style: TextStyle(
                fontSize: 12, color: AppTheme.textSecondary,
              )),
            ]),
          ),
          const Icon(Icons.chevron_right, color: AppTheme.textMuted),
        ]),
      ),
    );
  }

  Widget _buildStatsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.bgCard, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _statItem('Scans', '${_wifi.scanCount}', Icons.radar),
        _statItem('Sent', '${_ws.messagesSent}', Icons.send),
        _statItem('Interval', '${_wifi.scanInterval.inSeconds}s', Icons.timer),
      ]),
    );
  }

  Widget _statItem(String label, String value, IconData icon) {
    return Column(children: [
      Icon(icon, size: 18, color: AppTheme.textMuted),
      const SizedBox(height: 6),
      Text(value, style: GoogleFonts.jetBrainsMono(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
      Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
    ]);
  }
}
