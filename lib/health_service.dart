import 'package:health/health.dart';

import 'health_source.dart';

/// Contains one read result; null metrics mean no visible or usable value.
class HealthSnapshot {
  const HealthSnapshot({
    this.steps,
    this.heartRate,
    this.heartTime,
    this.sleep,
  });

  final int? steps;
  final num? heartRate;
  final DateTime? heartTime;
  final Duration? sleep;

  /// Indicates an authorized read with no displayable metrics.
  bool get isEmpty => steps == null && heartRate == null && sleep == null;
}

/// Owns bounded health queries and combines native records for the screen.
class HealthService {
  /// Allows deterministic native fixtures and a fixed clock in tests.
  HealthService({HealthSource? source, DateTime Function()? now})
    : _source = source ?? HealthSource(),
      _now = now ?? DateTime.now;

  final HealthSource _source;
  final DateTime Function() _now;

  /// Identifies the source for accurate authorization and metric descriptions.
  HealthBackend get backend => _source.backend;

  /// Checks provider availability after plugin configuration.
  Future<HealthAvailability?> availability() => _source.availability();

  /// Returns explicit Android grants or unknown HealthKit read access.
  Future<bool?> hasPermissions() => _source.hasPermissions();

  /// Requests read-only access through the native authorization UI.
  Future<void> requestPermissions() => _source.requestPermissions();

  /// Reads today's steps, the latest heart sample, and merged 24-hour sleep intervals.
  Future<HealthSnapshot> read() async {
    final now = _now();
    final midnight = DateTime(now.year, now.month, now.day);
    final yesterday = now.subtract(const Duration(hours: 24));
    final total = await _source.totalSteps(midnight, now);
    if (total != null && total < 0) {
      throw const FormatException('Invalid step aggregate.');
    }
    // A zero native aggregate can mean either an empty store or recorded zero.
    final stepRecords = total == 0 || total == null
        ? await _source.records(HealthDataType.STEPS, midnight, now)
        : null;
    final heart = List<HealthDataPoint>.of(
      await _source.records(
        HealthDataType.HEART_RATE,
        now.subtract(const Duration(days: 30)),
        now,
      ),
    )..sort((a, b) => b.dateFrom.compareTo(a.dateFrom));
    final latest = heart.isEmpty ? null : heart.first;
    final value = latest?.value;
    if (latest != null &&
        (value is! NumericHealthValue ||
            !value.numericValue.isFinite ||
            value.numericValue <= 0)) {
      throw const FormatException('Invalid heart-rate sample.');
    }
    final sessions = List<HealthDataPoint>.of(
      await _source.records(HealthDataType.SLEEP_SESSION, yesterday, now),
    )..sort((a, b) => a.dateFrom.compareTo(b.dateFrom));
    // Clip to the window and merge overlaps; never add stages to sessions.
    var duration = Duration.zero;
    var coveredUntil = yesterday;
    var foundSleep = false;
    for (final session in sessions) {
      final start = session.dateFrom.isBefore(coveredUntil)
          ? coveredUntil
          : session.dateFrom;
      final end = session.dateTo.isAfter(now) ? now : session.dateTo;
      if (end.isAfter(start)) {
        duration += end.difference(start);
        coveredUntil = end;
        foundSleep = true;
      }
    }
    return HealthSnapshot(
      steps: stepRecords?.isEmpty == true ? null : total,
      heartRate: value is NumericHealthValue ? value.numericValue : null,
      heartTime: latest?.dateFrom,
      sleep: foundSleep ? duration : null,
    );
  }
}
