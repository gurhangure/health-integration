import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';

/// Implements the app's plugin operations with synthetic data.
class FakeHealthPlugin extends Fake implements Health {
  bool authorizationCompletes = true;
  bool? granted = true;
  HealthConnectSdkStatus? sdkStatus = HealthConnectSdkStatus.sdkAvailable;
  int configurations = 0;
  int permissionChecks = 0;
  int? steps = 123;
  Object? failure;
  List<HealthDataType>? requestedTypes;
  List<HealthDataAccess>? requestedAccess;
  final data = <HealthDataType, List<HealthDataPoint>>{};
  final queries = <List<HealthDataType>>[];
  final windows = <(DateTime, DateTime)>[];

  /// Avoids native device information while verifying configuration ordering.
  @override
  Future<void> configure() async {
    configurations++;
  }

  /// Supplies Android SDK status independently of the test host's platform.
  @override
  Future<HealthConnectSdkStatus?> getHealthConnectSdkStatus() async =>
      sdkStatus;

  /// Models Android's explicit grant check, which HealthKit must never reuse.
  @override
  Future<bool?> hasPermissions(
    List<HealthDataType> types, {
    List<HealthDataAccess>? permissions,
  }) async {
    permissionChecks++;
    return granted;
  }

  /// Captures authorization scope so tests can reject accidental write requests.
  @override
  Future<bool> requestAuthorization(
    List<HealthDataType> types, {
    List<HealthDataAccess>? permissions,
  }) async {
    requestedTypes = List.of(types);
    requestedAccess = permissions == null ? null : List.of(permissions);
    return authorizationCompletes;
  }

  /// Supplies a native aggregate without querying a real health store.
  @override
  Future<int?> getTotalStepsInInterval(
    DateTime startTime,
    DateTime endTime, {
    bool includeManualEntry = true,
  }) async {
    if (failure != null) throw failure!;
    return steps;
  }

  /// Returns controlled category intervals and records the actual native types.
  @override
  Future<List<HealthDataPoint>> getHealthDataFromTypes({
    required List<HealthDataType> types,
    Map<HealthDataType, HealthDataUnit>? preferredUnits,
    required DateTime startTime,
    required DateTime endTime,
    List<RecordingMethod> recordingMethodsToFilter = const [],
  }) async {
    if (failure != null) throw failure!;
    queries.add(List.of(types));
    windows.add((startTime, endTime));
    // Model the plugin's iOS strictStartDate filter, not a live health store.
    return [for (final type in types) ...?data[type]]
        .where(
          (point) =>
              !point.dateFrom.isBefore(startTime) &&
              !point.dateFrom.isAfter(endTime),
        )
        .toList();
  }
}
