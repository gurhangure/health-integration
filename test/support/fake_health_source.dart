import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:health_connect_demo/health_controller.dart';
import 'package:health_connect_demo/health_service.dart';
import 'package:health_connect_demo/health_source.dart';

/// Fixes all query windows without depending on the machine's current date.
final fixtureNow = DateTime(2026, 10, 27, 12);

/// Supplies synthetic native records and records calls for boundary assertions.
class FakeHealthSource extends Fake implements HealthSource {
  HealthConnectSdkStatus? status = HealthConnectSdkStatus.sdkAvailable;
  bool granted = false;
  bool grantOnRequest = true;
  int? steps = 123;
  Object? failure;
  Completer<void>? availabilityGate;
  int requests = 0;
  int permissionChecks = 0;
  int availabilityChecks = 0;
  int totalReads = 0;
  final data = <HealthDataType, List<HealthDataPoint>>{};
  final queries = <({HealthDataType type, DateTime start, DateTime end})>[];
  (DateTime, DateTime)? stepWindow;

  /// Can hold availability pending to exercise loading and disposal behavior.
  @override
  Future<HealthConnectSdkStatus?> availability() async {
    availabilityChecks++;
    await availabilityGate?.future;
    if (failure != null) throw failure!;
    return status;
  }

  /// Returns the current grant, including simulated revocation.
  @override
  Future<bool> hasPermissions() async {
    permissionChecks++;
    return granted;
  }

  /// Simulates either full authorization or a denied/partial grant.
  @override
  Future<void> requestPermissions() async {
    requests++;
    granted = grantOnRequest;
  }

  /// Records the aggregate window without summing raw sources.
  @override
  Future<int?> totalSteps(DateTime start, DateTime end) async {
    totalReads++;
    stepWindow = (start, end);
    return steps;
  }

  /// Returns a fresh list just as a native query would.
  @override
  Future<List<HealthDataPoint>> records(
    HealthDataType type,
    DateTime start,
    DateTime end,
  ) async {
    queries.add((type: type, start: start, end: end));
    return List.of(data[type] ?? []);
  }
}

/// Builds a health record with synthetic provenance and no personal data.
HealthDataPoint point(
  HealthDataType type,
  DateTime start, {
  DateTime? end,
  num value = 72,
}) => HealthDataPoint(
  uuid: 'synthetic-${type.name}-${start.millisecondsSinceEpoch}',
  value: NumericHealthValue(numericValue: value),
  type: type,
  unit: type == HealthDataType.HEART_RATE
      ? HealthDataUnit.BEATS_PER_MINUTE
      : type == HealthDataType.STEPS
      ? HealthDataUnit.COUNT
      : HealthDataUnit.MINUTE,
  dateFrom: start,
  dateTo: end ?? start,
  sourcePlatform: HealthPlatformType.googleHealthConnect,
  sourceDeviceId: 'synthetic-device',
  sourceId: 'synthetic-source',
  sourceName: 'Synthetic fixture',
);

/// Provides the same representative sample to widget and device tests.
FakeHealthSource populatedSource() => FakeHealthSource()
  ..data[HealthDataType.HEART_RATE] = [
    point(
      HealthDataType.HEART_RATE,
      fixtureNow.subtract(const Duration(minutes: 5)),
    ),
  ]
  ..data[HealthDataType.SLEEP_SESSION] = [
    point(
      HealthDataType.SLEEP_SESSION,
      fixtureNow.subtract(const Duration(hours: 3)),
      end: fixtureNow.subtract(const Duration(hours: 1)),
    ),
  ];

/// Wires real presentation and processing to controlled native data.
HealthController fixtureController(FakeHealthSource source) => HealthController(
  service: HealthService(source: source, now: () => fixtureNow),
  isAndroid: true,
);
