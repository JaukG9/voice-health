import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_health/screens/settings_screen.dart';
import 'package:voice_health/services/app_store.dart';

void main() {
  testWidgets('analysis mode switch updates the UI immediately',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    // init() touches the real file system — run it outside fake-async.
    await tester.runAsync(() => AppStore.instance.init());

    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pump();

    // Device mode by default: no server fields visible.
    expect(AppStore.instance.analysisMode, 'device');
    expect(find.text('Test connection'), findsNothing);

    // Switching to server mode shows the server fields at once.
    await tester.tap(find.text('My computer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(AppStore.instance.analysisMode, 'server');
    expect(find.text('Test connection'), findsOneWidget);

    // And switching back hides them again.
    await tester.tap(find.text('This phone'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(AppStore.instance.analysisMode, 'device');
    expect(find.text('Test connection'), findsNothing);
  }, timeout: const Timeout(Duration(minutes: 1)));
}
