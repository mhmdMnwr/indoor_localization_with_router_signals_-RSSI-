import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'package:permission_handler/permission_handler.dart';

class RouterConfig {
  String bssid;
  final String label;
  double lastRssi;

  RouterConfig({required this.bssid, required this.label, this.lastRssi = -100.0});
}

class WifiScannerService extends ChangeNotifier {
  final WiFiScan _wifiScan = WiFiScan.instance;
  Timer? _scanTimer;
  bool _isScanning = false;
  bool _hasPermission = false;
  String? _errorMessage;
  List<WiFiAccessPoint> _lastScanResults = [];
  int _scanCount = 0;
  Duration _scanInterval = const Duration(seconds: 1);

  // 4 router BSSIDs — user configurable
  final List<RouterConfig> routers = [
    RouterConfig(bssid: '', label: 'Router 0 (0,0)'),
    RouterConfig(bssid: '', label: 'Router 1 (4,0)'),
    RouterConfig(bssid: '', label: 'Router 2 (0,2)'),
    RouterConfig(bssid: '', label: 'Router 3 (4,2)'),
  ];

  // Getters
  bool get isScanning => _isScanning;
  bool get hasPermission => _hasPermission;
  String? get errorMessage => _errorMessage;
  List<WiFiAccessPoint> get lastScanResults => _lastScanResults;
  int get scanCount => _scanCount;
  Duration get scanInterval => _scanInterval;

  bool get hasAllBssids => routers.every((r) => r.bssid.isNotEmpty);

  set scanInterval(Duration d) {
    _scanInterval = d;
    if (_isScanning) {
      stopScanning();
      startScanning();
    }
    notifyListeners();
  }

  /// Request all necessary permissions for WiFi scanning
  Future<bool> requestPermissions() async {
    // Location permission (required for WiFi scanning)
    final locationStatus = await Permission.locationWhenInUse.request();
    if (!locationStatus.isGranted) {
      _errorMessage = 'Location permission required for WiFi scanning';
      _hasPermission = false;
      notifyListeners();
      return false;
    }

    // Check if WiFi scan is available
    final canScan = await _wifiScan.canStartScan();
    if (canScan != CanStartScan.yes) {
      _errorMessage = 'WiFi scanning not available: $canScan';
      _hasPermission = false;
      notifyListeners();
      return false;
    }

    _hasPermission = true;
    _errorMessage = null;
    notifyListeners();
    return true;
  }

  /// Start periodic WiFi scanning
  void startScanning() {
    if (_isScanning) return;
    _isScanning = true;
    _scanCount = 0;
    notifyListeners();

    // Initial scan
    _performScan();

    // Periodic scans
    _scanTimer = Timer.periodic(_scanInterval, (_) => _performScan());
  }

  void stopScanning() {
    _scanTimer?.cancel();
    _scanTimer = null;
    _isScanning = false;
    notifyListeners();
  }

  Future<void> _performScan() async {
    try {
      // Trigger a new scan
      await _wifiScan.startScan();

      // Get results
      final canGet = await _wifiScan.canGetScannedResults();
      if (canGet != CanGetScannedResults.yes) return;

      final results = await _wifiScan.getScannedResults();
      _lastScanResults = results;
      _scanCount++;

      // Match RSSI values to configured routers
      for (final router in routers) {
        if (router.bssid.isEmpty) continue;
        final match = results.where(
          (ap) => ap.bssid.toLowerCase() == router.bssid.toLowerCase(),
        );
        if (match.isNotEmpty) {
          router.lastRssi = match.first.level.toDouble();
        }
      }

      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      debugPrint('[WiFi] Scan error: $e');
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  /// Get current RSSI values for all 4 routers (in order)
  List<double> getCurrentRssi() {
    return routers.map((r) => r.lastRssi).toList();
  }

  /// Update a router's BSSID
  void setRouterBssid(int index, String bssid) {
    if (index >= 0 && index < routers.length) {
      routers[index].bssid = bssid.trim().toLowerCase();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    stopScanning();
    super.dispose();
  }
}
