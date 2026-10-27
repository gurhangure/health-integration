import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:health_connect_demo/main.dart';
import 'package:health_connect_demo/health_source.dart';

import '../support/fake_health_source.dart';

/// Verifies Apple Health UI states without invoking native permissions or data.
void main() {
  testWidgets(
    'hidden read denial explains empty data and offers Health access',
    (tester) async {
      final source = FakeHealthSource()
        ..backend = HealthBackend.healthKit
        ..steps = 0;
      final controller = fixtureController(source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(HealthApp(controller: controller));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Apple Health hides read permission status'),
        findsOneWidget,
      );
      expect(find.textContaining('Permissions are granted'), findsNothing);
      final review = find.text('Review Health access');
      await tester.scrollUntilVisible(review, 200);
      await tester.tap(review);
      await tester.pumpAndSettle();
      expect(source.requests, 1);
      expect(
        find.textContaining('Apple Health hides read permission status'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Apple data and partial access preserve shared metric formatting',
    (tester) async {
      final source = populatedAppleSource();
      final controller = fixtureController(source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(HealthApp(controller: controller));
      await tester.pumpAndSettle();
      expect(find.textContaining('123\n'), findsOneWidget);
      expect(find.textContaining('72 bpm'), findsOneWidget);
      expect(find.textContaining('2 h 0 min'), findsOneWidget);
      expect(find.textContaining('recorded sleep intervals'), findsOneWidget);
      expect(source.requests, 0);
      final refresh = find.text('Refresh');
      source.data.remove(HealthDataType.HEART_RATE);
      await tester.scrollUntilVisible(refresh, 200);
      await tester.tap(refresh);
      await tester.pumpAndSettle();
      expect(find.textContaining('123\n'), findsOneWidget);
      expect(find.textContaining('72 bpm'), findsNothing);
      expect(find.textContaining('No data available\n'), findsOneWidget);
      source.data.clear();
      source.steps = 0;
      await tester.scrollUntilVisible(refresh, 200);
      await tester.tap(refresh);
      await tester.pumpAndSettle();
      expect(find.textContaining('72 bpm'), findsNothing);
      expect(find.textContaining('read access is not allowed'), findsOneWidget);
    },
  );

  testWidgets(
    'restricted authorization gives guidance and retry keeps the app usable',
    (tester) async {
      final source = FakeHealthSource()
        ..backend = HealthBackend.healthKit
        ..authorizationCompletes = false
        ..steps = 0;
      final controller = fixtureController(source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(HealthApp(controller: controller));
      await tester.pumpAndSettle();
      final review = find.text('Review Health access');
      await tester.scrollUntilVisible(review, 200);
      await tester.tap(review);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('authorization could not complete'),
        findsOneWidget,
      );
      expect(find.textContaining('device restrictions'), findsOneWidget);
      source.authorizationCompletes = true;
      await tester.scrollUntilVisible(review, 200);
      await tester.tap(review);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Apple Health hides read permission status'),
        findsOneWidget,
      );
    },
  );
  testWidgets('unavailable Apple Health offers refresh without authorization', (
    tester,
  ) async {
    final source = FakeHealthSource()
      ..backend = HealthBackend.healthKit
      ..status = HealthAvailability.unavailable;
    final controller = fixtureController(source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(HealthApp(controller: controller));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Apple Health is unavailable or restricted'),
      findsOneWidget,
    );
    expect(find.text('Review Health access'), findsNothing);
    expect(find.text('Refresh'), findsOneWidget);
    expect(source.requests, 0);
    expect(source.totalReads, 0);
  });
}
