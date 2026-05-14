import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/wifi_scanner_service.dart';

/// Data collection screen for fingerprinting.
/// User selects a grid cell, then collects RSSI data for ~2 minutes.
class DataCollectionScreen extends StatefulWidget {
  final WifiScannerService wifiScanner;
  final String serverBaseUrl; // e.g. "http://10.98.21.110:6060"

  const DataCollectionScreen({
    super.key,
    required this.wifiScanner,
    required this.serverBaseUrl,
  });

  @override
  State<DataCollectionScreen> createState() => _DataCollectionScreenState();
}

class _DataCollectionScreenState extends State<DataCollectionScreen> {
  static const int gridCols = 5;
  static const int gridRows = 3;
  static const int collectionDurationSec = 120; // 2 minutes

  int _selectedCol = -1;
  int _selectedRow = -1;
  bool _isCollecting = false;
  int _samplesSent = 0;
  int _secondsRemaining = collectionDurationSec;
  Timer? _collectionTimer;
  Timer? _countdownTimer;
  String _statusMessage = 'Select a grid cell to start collecting data';
  Map<String, int> _cellCounts = {};

  @override
  void initState() {
    super.initState();
    _fetchCellCounts();
  }

  @override
  void dispose() {
    _stopCollection();
    super.dispose();
  }

  Future<void> _fetchCellCounts() async {
    try {
      final resp = await http.get(
        Uri.parse('${widget.serverBaseUrl}/collect/status'),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() {
          _cellCounts = Map<String, int>.from(data['cells'] ?? {});
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch cell counts: $e');
    }
  }

  void _selectCell(int col, int row) {
    if (_isCollecting) return;
    setState(() {
      _selectedCol = col;
      _selectedRow = row;
      _statusMessage = 'Cell ($col, $row) selected. Press START to collect.';
    });
  }

  void _startCollection() {
    if (_selectedCol < 0 || _selectedRow < 0) return;
    if (!widget.wifiScanner.hasAllBssids) {
      setState(() {
        _statusMessage = '⚠️ Configure all 4 router BSSIDs first!';
      });
      return;
    }

    setState(() {
      _isCollecting = true;
      _samplesSent = 0;
      _secondsRemaining = collectionDurationSec;
      _statusMessage = 'Collecting at ($_selectedCol, $_selectedRow)...';
    });

    // Send RSSI every 1 second
    _collectionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _sendSample();
    });

    // Countdown timer
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _secondsRemaining--;
      });
      if (_secondsRemaining <= 0) {
        _stopCollection();
        setState(() {
          _statusMessage =
              '✅ Done! Collected $_samplesSent samples for ($_selectedCol, $_selectedRow)';
        });
        _fetchCellCounts();
      }
    });

    // Start scanning if not already
    if (!widget.wifiScanner.isScanning) {
      widget.wifiScanner.startScanning();
    }
  }

  void _stopCollection() {
    _collectionTimer?.cancel();
    _countdownTimer?.cancel();
    _collectionTimer = null;
    _countdownTimer = null;
    setState(() {
      _isCollecting = false;
    });
  }

  Future<void> _sendSample() async {
    final rssi = widget.wifiScanner.getCurrentRssi();
    // Check if we have real data (not all -100)
    if (rssi.every((r) => r <= -99)) return;

    try {
      final resp = await http.post(
        Uri.parse('${widget.serverBaseUrl}/collect'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'cell_col': _selectedCol,
          'cell_row': _selectedRow,
          'rssi': rssi,
        }),
      );

      if (resp.statusCode == 200) {
        setState(() {
          _samplesSent++;
        });
      }
    } catch (e) {
      debugPrint('Send error: $e');
    }
  }

  Future<void> _resetData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset All Data?'),
        content: const Text(
            'This will delete ALL collected fingerprint data. Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await http.delete(
          Uri.parse('${widget.serverBaseUrl}/collect/reset'),
        );
        _fetchCellCounts();
        setState(() {
          _statusMessage = 'Data reset successfully';
        });
      } catch (e) {
        debugPrint('Reset error: $e');
      }
    }
  }

  int _getCellCount(int col, int row) {
    return _cellCounts['($col,$row)'] ?? 0;
  }

  Color _getCellColor(int col, int row) {
    final count = _getCellCount(col, row);
    if (col == _selectedCol && row == _selectedRow) {
      return _isCollecting
          ? Colors.amber.withOpacity(0.4)
          : Colors.blue.withOpacity(0.3);
    }
    if (count >= 60) return Colors.green.withOpacity(0.3);
    if (count >= 30) return Colors.orange.withOpacity(0.2);
    if (count > 0) return Colors.yellow.withOpacity(0.15);
    return Colors.white.withOpacity(0.05);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📊 Data Collection'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchCellCounts,
            tooltip: 'Refresh counts',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: _resetData,
            tooltip: 'Reset all data',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Status message
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blueGrey.shade900,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    _isCollecting ? Icons.sensors : Icons.info_outline,
                    color: _isCollecting ? Colors.amber : Colors.blueAccent,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _statusMessage,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Collection progress
            if (_isCollecting) ...[
              LinearProgressIndicator(
                value: 1.0 - (_secondsRemaining / collectionDurationSec),
                backgroundColor: Colors.grey.shade800,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
              ),
              const SizedBox(height: 8),
              Text(
                '${_secondsRemaining}s remaining  •  $_samplesSent samples sent',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              ),
              const SizedBox(height: 16),
            ],

            // Grid — 5×3 = 15 cells
            Expanded(
              child: AspectRatio(
                aspectRatio: 5 / 3,
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: gridCols,
                    childAspectRatio: 1.2,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  // Build bottom-to-top so row 0 is at bottom (matching room)
                  itemCount: gridCols * gridRows,
                  itemBuilder: (ctx, index) {
                    final row = gridRows - 1 - (index ~/ gridCols);
                    final col = index % gridCols;
                    final count = _getCellCount(col, row);
                    final isSelected =
                        col == _selectedCol && row == _selectedRow;

                    return GestureDetector(
                      onTap: () => _selectCell(col, row),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        decoration: BoxDecoration(
                          color: _getCellColor(col, row),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? (_isCollecting
                                    ? Colors.amber
                                    : Colors.blue)
                                : Colors.grey.shade700,
                            width: isSelected ? 2.5 : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '($col,$row)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: isSelected
                                    ? Colors.white
                                    : Colors.grey.shade400,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$count',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: count >= 60
                                    ? Colors.greenAccent
                                    : count > 0
                                        ? Colors.orangeAccent
                                        : Colors.grey.shade600,
                              ),
                            ),
                            Text(
                              'samples',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Legend
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _legendDot(Colors.green, '≥60'),
                const SizedBox(width: 16),
                _legendDot(Colors.orange, '≥30'),
                const SizedBox(width: 16),
                _legendDot(Colors.yellow, '>0'),
                const SizedBox(width: 16),
                _legendDot(Colors.grey, 'Empty'),
              ],
            ),
            const SizedBox(height: 16),

            // Start/Stop button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _isCollecting ? _stopCollection : _startCollection,
                icon: Icon(_isCollecting ? Icons.stop : Icons.play_arrow),
                label: Text(
                  _isCollecting ? 'STOP COLLECTION' : 'START COLLECTION',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _isCollecting ? Colors.red.shade700 : Colors.blue.shade700,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color.withOpacity(0.5),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
      ],
    );
  }
}
