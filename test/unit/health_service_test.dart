import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:health_connect_demo/health_service.dart';

import '../support/fake_health_source.dart';

/// Verifies query windows, missing values, validation, and interval processing.
void main() {
  late FakeHealthSource source;
  late HealthService service;

  setUp(() {
    source = FakeHealthSource();
    service = HealthService(source: source, now: () => fixtureNow);
  });

  test('uses native step aggregate and bounded metric windows', () async {
    final snapshot = await service.read();
    expect(snapshot.steps, 123);
    expect(source.stepWindow, (DateTime(2026, 10, 27), fixtureNow));
    expect(source.queries, [
      (
        type: HealthDataType.HEART_RATE,
        start: fixtureNow.subtract(const Duration(days: 30)),
        end: fixtureNow,
      ),
      (
        type: HealthDataType.SLEEP_SESSION,
        start: fixtureNow.subtract(const Duration(hours: 24)),
        end: fixtureNow,
      ),
    ]);
  });

  test('distinguishes absent steps from a recorded zero', () async {
    source.steps = 0;
    expect((await service.read()).steps, isNull);
    source.data[HealthDataType.STEPS] = [
      point(HealthDataType.STEPS, fixtureNow, value: 0),
    ];
    expect((await service.read()).steps, 0);
  });

  test('a null aggregate remains unknown even if raw records exist', () async {
    source.steps = null;
    source.data[HealthDataType.STEPS] = [
      point(HealthDataType.STEPS, fixtureNow, value: 10),
    ];
    expect((await service.read()).steps, isNull);
  });

  test('selects the newest heart sample from unordered records', () async {
    final older = fixtureNow.subtract(const Duration(days: 1));
    final latest = fixtureNow.subtract(const Duration(minutes: 5));
    source.data[HealthDataType.HEART_RATE] = [
      point(HealthDataType.HEART_RATE, older, value: 65),
      point(HealthDataType.HEART_RATE, latest, value: 81),
    ];
    final snapshot = await service.read();
    expect(snapshot.heartRate, 81);
    expect(snapshot.heartTime, latest);
  });

  test(
    'clips, sorts, and merges duplicate and overlapping sleep intervals',
    () async {
      final start = fixtureNow.subtract(const Duration(hours: 24));
      source.data[HealthDataType.SLEEP_SESSION] = [
        point(
          HealthDataType.SLEEP_SESSION,
          fixtureNow.subtract(const Duration(hours: 1)),
          end: fixtureNow.add(const Duration(hours: 2)),
        ),
        point(
          HealthDataType.SLEEP_SESSION,
          start.subtract(const Duration(hours: 2)),
          end: start.add(const Duration(hours: 2)),
        ),
        point(
          HealthDataType.SLEEP_SESSION,
          start.add(const Duration(hours: 1)),
          end: start.add(const Duration(hours: 4)),
        ),
        point(
          HealthDataType.SLEEP_SESSION,
          start.add(const Duration(hours: 1)),
          end: start.add(const Duration(hours: 4)),
        ),
        point(HealthDataType.SLEEP_SESSION, start, end: start),
        point(
          HealthDataType.SLEEP_SESSION,
          start.add(const Duration(hours: 5)),
          end: start,
        ),
      ];
      expect((await service.read()).sleep, const Duration(hours: 5));
    },
  );

  test('returns an empty snapshot when every query has no records', () async {
    source.steps = 0;
    final snapshot = await service.read();
    expect(snapshot.isEmpty, isTrue);
    expect(snapshot.sleep, isNull);
    expect(snapshot.heartTime, isNull);
  });

  test('rejects negative aggregates and invalid heart values', () async {
    source.steps = -1;
    await expectLater(service.read(), throwsFormatException);
    source.steps = 1;
    for (final value in [0, -1, double.nan, double.infinity]) {
      source.data[HealthDataType.HEART_RATE] = [
        point(HealthDataType.HEART_RATE, fixtureNow, value: value),
      ];
      await expectLater(service.read(), throwsFormatException);
    }
  });
}
