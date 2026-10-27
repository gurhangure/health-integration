import 'package:health/health.dart';

/// Isolates native Health Connect calls from processing and presentation.
class HealthSource {
  HealthSource() : _health = Health();

  final Health _health;
  static const _types = [
    HealthDataType.STEPS,
    HealthDataType.HEART_RATE,
    HealthDataType.SLEEP_SESSION,
  ];
  static const _access = [
    HealthDataAccess.READ,
    HealthDataAccess.READ,
    HealthDataAccess.READ,
  ];

  /// Configures the plugin before checking the Android provider.
  Future<HealthConnectSdkStatus?> availability() async {
    await _health.configure();
    return _health.getHealthConnectSdkStatus();
  }

  /// Requires all three read grants, including after a partial authorization.
  Future<bool> hasPermissions() async =>
      await _health.hasPermissions(_types, permissions: _access) == true;

  /// Opens system authorization; callers must recheck the actual grants.
  Future<void> requestPermissions() async {
    await _health.requestAuthorization(_types, permissions: _access);
  }

  /// Uses native aggregation to avoid double counting overlapping step sources.
  Future<int?> totalSteps(DateTime start, DateTime end) =>
      _health.getTotalStepsInInterval(start, end);

  /// Reads one record type within a bounded interval without persisting it.
  Future<List<HealthDataPoint>> records(
    HealthDataType type,
    DateTime start,
    DateTime end,
  ) => _health.getHealthDataFromTypes(
    types: [type],
    startTime: start,
    endTime: end,
  );
}
