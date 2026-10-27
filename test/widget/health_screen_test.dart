import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:health_connect_demo/health_controller.dart';
import 'package:health_connect_demo/main.dart';

import '../support/fake_health_source.dart';

/// Verifies visible states, accessible status, and the screen's user actions.
void main() {
  testWidgets('shows loading and disables refresh while a read is pending', (
    tester,
  ) async {
    final source = populatedSource()..availabilityGate = Completer<void>();
    final controller = fixtureController(source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(HealthApp(controller: controller));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    expect(button.onPressed, isNull);
    expect(find.text('Grant read permissions'), findsNothing);
    source.availabilityGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets(
    'grants access through an explicit action and renders all metrics',
    (tester) async {
      final source = populatedSource();
      final controller = fixtureController(source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(HealthApp(controller: controller));
      await tester.pumpAndSettle();
      expect(source.requests, 0);
      final grant = find.text('Grant read permissions');
      await tester.ensureVisible(grant);
      await tester.tap(grant);
      await tester.pumpAndSettle();
      expect(source.requests, 1);
      expect(find.textContaining('123\n'), findsOneWidget);
      expect(find.textContaining('72 bpm'), findsOneWidget);
      expect(find.textContaining('2 h 0 min'), findsOneWidget);
      expect(grant, findsNothing);
    },
  );

  testWidgets(
    'refresh after revocation removes previously visible health values',
    (tester) async {
      final source = populatedSource()..granted = true;
      final controller = fixtureController(source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(HealthApp(controller: controller));
      await tester.pumpAndSettle();
      source.granted = false;
      final refresh = find.text('Refresh');
      await tester.ensureVisible(refresh);
      await tester.tap(refresh);
      await tester.pumpAndSettle();
      expect(find.textContaining('72 bpm'), findsNothing);
      expect(find.text('Grant read permissions'), findsOneWidget);
      expect(find.textContaining('—\n'), findsNWidgets(3));
    },
  );

  testWidgets('empty results explain how to add records and announce status', (
    tester,
  ) async {
    final source = FakeHealthSource()
      ..granted = true
      ..steps = 0;
    final controller = fixtureController(source);
    addTearDown(controller.dispose);
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    await tester.pumpWidget(HealthApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.textContaining('Permissions are granted'), findsOneWidget);
    expect(find.textContaining('No data available\n'), findsNWidgets(3));
    expect(
      tester.getSemantics(find.byKey(const ValueKey('status'))),
      matchesSemantics(
        label: controller.state.message,
        isLiveRegion: true,
        textDirection: TextDirection.ltr,
      ),
    );
  });

  testWidgets('provider errors give a safe message and refresh recovers', (
    tester,
  ) async {
    final source = populatedSource()
      ..granted = true
      ..failure = StateError('private native payload');
    final controller = fixtureController(source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(HealthApp(controller: controller));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Unable to read Health Connect'),
      findsOneWidget,
    );
    expect(find.textContaining('private native payload'), findsNothing);
    source.failure = null;
    final refresh = find.text('Refresh');
    await tester.ensureVisible(refresh);
    await tester.tap(refresh);
    await tester.pumpAndSettle();
    expect(find.textContaining('72 bpm'), findsOneWidget);
  });

  testWidgets('unavailable provider does not offer authorization', (
    tester,
  ) async {
    final source = FakeHealthSource()
      ..status = HealthConnectSdkStatus.sdkUnavailable;
    final controller = fixtureController(source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(HealthApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.textContaining('Health Connect unavailable'), findsOneWidget);
    expect(find.text('Grant read permissions'), findsNothing);
  });

  testWidgets('iOS explains its platform limitation without requesting data', (
    tester,
  ) async {
    final controller = HealthController(isAndroid: false);
    addTearDown(controller.dispose);
    await tester.pumpWidget(HealthApp(controller: controller));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('HealthKit reading is not implemented'),
      findsOneWidget,
    );
    expect(find.text('Grant read permissions'), findsNothing);
  });

  testWidgets('large text remains scrollable without layout errors', (
    tester,
  ) async {
    final source = populatedSource()..granted = true;
    final controller = fixtureController(source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: HealthScreen(controller: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Refresh'));
    expect(tester.takeException(), isNull);
  });
}
