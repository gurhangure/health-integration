import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import 'health_service.dart';

/// Describes the mutually exclusive states of a health read.
enum HealthPhase {
  idle,
  loading,
  unavailable,
  permission,
  empty,
  ready,
  failure,
}

/// Immutable presentation state; only successful reads carry health values.
class HealthState {
  const HealthState({required this.phase, required this.message, this.data});

  final HealthPhase phase;
  final String message;
  final HealthSnapshot? data;
}

/// Coordinates availability, authorization, and reads without widget side effects.
class HealthController extends ChangeNotifier {
  /// Allows isolated service tests and a platform override for device fixtures.
  HealthController({HealthService? service, bool? isAndroid})
    : _service = service ?? HealthService(),
      _isAndroid = isAndroid ?? Platform.isAndroid;

  final HealthService _service;
  final bool _isAndroid;
  bool _busy = false;
  bool _disposed = false;
  HealthState _state = const HealthState(phase: HealthPhase.idle, message: '');

  /// Exposes the current immutable state to listeners.
  HealthState get state => _state;

  /// Rechecks access before every read and ignores overlapping refresh requests.
  Future<void> refresh({bool requestPermission = false}) async {
    if (_busy || _disposed) return;
    _busy = true;
    _publish(
      const HealthState(phase: HealthPhase.loading, message: 'Loading…'),
    );
    try {
      if (!_isAndroid) {
        _publish(
          const HealthState(
            phase: HealthPhase.unavailable,
            message:
                'Health Connect is available on Android only. '
                'HealthKit reading is not implemented in this demo.',
          ),
        );
        return;
      }
      final availability = await _service.availability();
      if (_disposed) return;
      if (availability == null) {
        throw StateError('Could not check provider availability.');
      }
      if (availability != HealthConnectSdkStatus.sdkAvailable) {
        _publish(
          const HealthState(
            phase: HealthPhase.unavailable,
            message:
                'Health Connect unavailable. Install or update Health Connect '
                'and Android system updates, then tap Refresh.',
          ),
        );
        return;
      }
      var granted = await _service.hasPermissions();
      if (_disposed) return;
      if (!granted && requestPermission) {
        await _service.requestPermissions();
        if (_disposed) return;
        granted = await _service.hasPermissions();
        if (_disposed) return;
      }
      if (!granted) {
        _publish(
          const HealthState(
            phase: HealthPhase.permission,
            message:
                'Permission not granted. Allow read access to steps, heart '
                'rate and sleep. If the prompt does not appear, open Health '
                'Connect → App permissions → Health Connect Demo.',
          ),
        );
        return;
      }
      final data = await _service.read();
      _publish(
        HealthState(
          phase: data.isEmpty ? HealthPhase.empty : HealthPhase.ready,
          message: data.isEmpty
              ? 'No data available. Permissions are granted. Add records using '
                    'a connected health app or Health Connect Toolbox, then Refresh.'
              : 'Updated. Missing values mean no records in that time window.',
          data: data,
        ),
      );
    } catch (_) {
      // Native exceptions may contain sensitive data; never display or log them.
      _publish(
        const HealthState(
          phase: HealthPhase.failure,
          message:
              'Unable to read Health Connect. Check permissions and provider '
              'updates, then tap Refresh to retry.',
        ),
      );
    } finally {
      _busy = false;
    }
  }

  /// Publishes a complete state only while listeners can still observe it.
  void _publish(HealthState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  /// Prevents in-flight completions from notifying or starting further work.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
