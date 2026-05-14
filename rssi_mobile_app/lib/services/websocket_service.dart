import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum WsConnectionState { disconnected, connecting, connected, error }

class PositionData {
  final double x;
  final double y;
  final double z;

  const PositionData({required this.x, required this.y, required this.z});

  factory PositionData.fromJson(Map<String, dynamic> json) {
    final pos = json['position'] as Map<String, dynamic>;
    return PositionData(
      x: (pos['x'] as num).toDouble(),
      y: (pos['y'] as num).toDouble(),
      z: (pos['z'] as num).toDouble(),
    );
  }

  @override
  String toString() => '(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)})';
}

class WebSocketService extends ChangeNotifier {
  WebSocketChannel? _channel;
  WsConnectionState _state = WsConnectionState.disconnected;
  PositionData? _lastPosition;
  String? _errorMessage;
  String _serverUrl = 'ws://10.98.21.110:6060/ws/mobile';
  int _messagesSent = 0;

  WsConnectionState get state => _state;
  PositionData? get lastPosition => _lastPosition;
  String? get errorMessage => _errorMessage;
  String get serverUrl => _serverUrl;
  int get messagesSent => _messagesSent;
  bool get isConnected => _state == WsConnectionState.connected;

  set serverUrl(String url) {
    _serverUrl = url;
    notifyListeners();
  }

  Future<void> connect() async {
    if (_state == WsConnectionState.connected) return;
    _state = WsConnectionState.connecting;
    _errorMessage = null;
    notifyListeners();

    try {
      final uri = Uri.parse(_serverUrl);
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;
      _state = WsConnectionState.connected;
      _messagesSent = 0;
      notifyListeners();

      _channel!.stream.listen(
        (data) {
          try {
            final json = jsonDecode(data as String) as Map<String, dynamic>;
            if (json.containsKey('status') && json['status'] == 'ok' && json.containsKey('position')) {
              _lastPosition = PositionData.fromJson(json);
              notifyListeners();
            } else if (json.containsKey('error')) {
              _errorMessage = json['error'] as String;
              notifyListeners();
            }
          } catch (e) {
            debugPrint('[WS] Parse error: $e');
          }
        },
        onError: (error) {
          _state = WsConnectionState.error;
          _errorMessage = error.toString();
          notifyListeners();
        },
        onDone: () {
          _state = WsConnectionState.disconnected;
          notifyListeners();
        },
      );
    } catch (e) {
      _state = WsConnectionState.error;
      _errorMessage = 'Failed to connect: $e';
      notifyListeners();
    }
  }

  void sendRssi(List<double> rssiValues) {
    if (_state != WsConnectionState.connected || _channel == null) return;
    if (rssiValues.length != 4) return;
    try {
      _channel!.sink.add(jsonEncode({'rssi': rssiValues}));
      _messagesSent++;
      notifyListeners();
    } catch (e) {
      debugPrint('[WS] Send error: $e');
    }
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
    _state = WsConnectionState.disconnected;
    _lastPosition = null;
    _messagesSent = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
