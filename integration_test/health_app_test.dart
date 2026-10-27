import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_connect_demo/main.dart' as app;
import 'package:integration_test/integration_test.dart';

import '../test/support/fake_health_source.dart';

/// Runs representative journeys in a real mobile app with synthetic native data.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('authorize, view metrics, refresh, and revoke access', (
    tester,
  ) async {
    final source = populatedSource();
    final controller = fixtureController(source);
    addTearDown(controller.dispose);
    runApp(app.HealthApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.textContaining('Permission not granted'), findsOneWidget);
    expect(source.totalReads, 0);

    final grant = find.text('Grant read permissions');
    await tester.ensureVisible(grant);
    await tester.tap(grant);
    await tester.pumpAndSettle();
    expect(find.textContaining('123\n'), findsOneWidget);
    expect(find.textContaining('72 bpm'), findsOneWidget);
    expect(find.textContaining('2 h 0 min'), findsOneWidget);

    source.steps = 456;
    final refresh = find.text('Refresh');
    await tester.ensureVisible(refresh);
    await tester.tap(refresh);
    await tester.pumpAndSettle();
    expect(find.textContaining('456\n'), findsOneWidget);

    source.granted = false;
    await tester.ensureVisible(refresh);
    await tester.tap(refresh);
    await tester.pumpAndSettle();
    expect(find.textContaining('72 bpm'), findsNothing);
    expect(find.text('Grant read permissions'), findsOneWidget);
    expect(source.totalReads, 2);
  }, timeout: const Timeout(Duration(minutes: 2)));

  if (Platform.isIOS) {
    testWidgets(
      'normal iOS launch explains that HealthKit is not implemented',
      (tester) async {
        app.main();
        await tester.pumpAndSettle();
        expect(
          find.textContaining('HealthKit reading is not implemented'),
          findsOneWidget,
        );
        expect(find.text('Grant read permissions'), findsNothing);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
