import 'package:flutter_test/flutter_test.dart';
import 'package:rssi_scanner/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const RssiScannerApp());
    expect(find.text('RSSI Scanner'), findsOneWidget);
  });
}
