import 'package:flutter/material.dart';
import 'package:rssi_scanner/theme.dart';
import 'package:rssi_scanner/screens/home_screen.dart';

void main() {
  runApp(const RssiScannerApp());
}

class RssiScannerApp extends StatelessWidget {
  const RssiScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RSSI Scanner',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const HomeScreen(),
    );
  }
}
