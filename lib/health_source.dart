import 'dart:io';

import 'package:flutter/services.dart';
import 'package:health/health.dart';

/// Identifies the native store without exposing platform checks to widgets.
enum HealthBackend { healthConnect, healthKit, unsupported }

/// Describes provider availability independently of either native SDK.
enum HealthAvailability { available, unavailable }

/// Indicates that a HealthKit authorization request could not complete.
class HealthAuthorizationException implements Exception {
  const HealthAuthorizationException();
}

/// Isolates native availability, read permissions, and record-type mappings.
class HealthSource {
  /// Injects the plugin, platform, and existing plugin channel for isolated tests.
  HealthSource({Health? health, HealthBackend? backend, MethodChannel? channel})
    : _health = health ?? Health(),
      backend = backend ?? _detectBackend(),
      _channel = channel ?? const MethodChannel('flutter_health');

  final Health _health;
  final MethodChannel _channel;
  final HealthBackend backend;

  static const _appleSleepTypes = [
    HealthDataType.SLEEP_IN_BED,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_AWAKE,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_REM,
  ];

  /// Detects supported mobile stores only at the native boundary.
  static HealthBackend _detectBackend() => Platform.isAndroid
      ? HealthBackend.healthConnect
      : Platform.isIOS
      ? HealthBackend.healthKit
      : HealthBackend.unsupported;

  /// Lists read-only types; Apple's sleep aliases share one sleepAnalysis grant.
  List<HealthDataType> get readTypes => backend == HealthBackend.healthKit
      ? const [
          HealthDataType.STEPS,
          HealthDataType.HEART_RATE,
          ..._appleSleepTypes,
        ]
      : const [
          HealthDataType.STEPS,
          HealthDataType.HEART_RATE,
          HealthDataType.SLEEP_SESSION,
        ];

  /// Maps a shared metric to supported native types without inventing sessions.
  List<HealthDataType> typesFor(HealthDataType type) {
    if (![
      HealthDataType.STEPS,
      HealthDataType.HEART_RATE,
      HealthDataType.SLEEP_SESSION,
    ].contains(type)) {
      throw ArgumentError.value(type, 'type', 'Unsupported health metric');
    }
    return backend == HealthBackend.healthKit &&
            type == HealthDataType.SLEEP_SESSION
        ? _appleSleepTypes
        : [type];
  }

  /// Configures the plugin and checks the provider before any record queries.
  Future<HealthAvailability?> availability() async {
    if (backend == HealthBackend.unsupported) {
      return HealthAvailability.unavailable;
    }
    await _health.configure();
    if (backend == HealthBackend.healthKit) {
      // health 13.3.2 implements this native method but exposes no Dart wrapper.
      final available = await _channel.invokeMethod<bool>(
        'checkIfHealthDataAvailable',
      );
      return available == null
          ? null
          : available
          ? HealthAvailability.available
          : HealthAvailability.unavailable;
    }
    final status = await _health.getHealthConnectSdkStatus();
    return status == null
        ? null
        : status == HealthConnectSdkStatus.sdkAvailable
        ? HealthAvailability.available
        : HealthAvailability.unavailable;
  }

  /// Returns unknown for HealthKit, which deliberately hides read-access grants.
  Future<bool?> hasPermissions() async {
    if (backend == HealthBackend.healthKit) return null;
    if (backend == HealthBackend.unsupported) return false;
    return await _health.hasPermissions(
          readTypes,
          permissions: List.filled(readTypes.length, HealthDataAccess.READ),
        ) ==
        true;
  }

  /// Requests reads only; iOS completion does not prove the user allowed reads.
  Future<void> requestPermissions() async {
    final completed = await _health.requestAuthorization(
      readTypes,
      permissions: List.filled(readTypes.length, HealthDataAccess.READ),
    );
    if (backend == HealthBackend.healthKit && !completed) {
      throw const HealthAuthorizationException();
    }
  }

  /// Uses the platform's native step aggregation rather than summing raw sources.
  Future<int?> totalSteps(DateTime start, DateTime end) =>
      _health.getTotalStepsInInterval(start, end);

  /// Reads native intervals; an iOS sleep buffer includes ordinary crossing nights.
  Future<List<HealthDataPoint>> records(
    HealthDataType type,
    DateTime start,
    DateTime end,
  ) => _health.getHealthDataFromTypes(
    types: typesFor(type),
    // The plugin uses strictStartDate on iOS; the service clips the extra day.
    startTime:
        backend == HealthBackend.healthKit &&
            type == HealthDataType.SLEEP_SESSION
        ? start.subtract(const Duration(days: 1))
        : start,
    endTime: end,
  );
}
