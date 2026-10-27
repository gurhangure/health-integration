import 'package:flutter/foundation.dart';

import 'health_service.dart';
import 'health_source.dart';

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
  const HealthState({
    required this.phase,
    required this.message,
    this.data,
    this.canRequestPermission = false,
  });

  final HealthPhase phase;
  final String message;
  final HealthSnapshot? data;
  final bool canRequestPermission;
}

/// Coordinates availability, authorization, and reads without widget side effects.
class HealthController extends ChangeNotifier {
  /// Allows isolated tests without performing platform checks in presentation.
  HealthController({HealthService? service})
    : _service = service ?? HealthService();

  final HealthService _service;
  bool _busy = false;
  bool _disposed = false;
  HealthState _state = const HealthState(phase: HealthPhase.idle, message: '');

  /// Exposes the current immutable state to listeners.
  HealthState get state => _state;

  /// HealthKit never exposes whether read access was granted or revoked.
  bool get _privateReadAccess => _service.backend == HealthBackend.healthKit;

  /// Names the explicit authorization action for the current native store.
  String get permissionActionLabel =>
      _privateReadAccess ? 'Review Health access' : 'Grant read permissions';

  /// Keeps the sleep label truthful about Apple's category-based intervals.
  String get sleepDetail => _privateReadAccess
      ? 'Last 24 hours • recorded sleep intervals, including in-bed and awake time'
      : 'Last 24 hours • session duration, including awake time';

  /// Names the provider in actionable errors without exposing native payloads.
  String get _provider =>
      _privateReadAccess ? 'Apple Health' : 'Health Connect';

  /// Rechecks access before every read and ignores overlapping refresh requests.
  Future<void> refresh({bool requestPermission = false}) async {
    if (_busy || _disposed) return;
    _busy = true;
    _publish(
      const HealthState(phase: HealthPhase.loading, message: 'Loading…'),
    );
    try {
      final availability = await _service.availability();
      if (_disposed) return;
      if (availability == null) {
        throw StateError('Could not check provider availability.');
      }
      if (availability != HealthAvailability.available) {
        _publish(
          HealthState(
            phase: HealthPhase.unavailable,
            message: _privateReadAccess
                ? 'Apple Health is unavailable or restricted on this device. Check device restrictions and try Refresh.'
                : _service.backend == HealthBackend.unsupported
                ? 'Health data is available on Android and iOS only.'
                : 'Health Connect unavailable. Install or update Health Connect '
                      'and Android system updates, then tap Refresh.',
          ),
        );
        return;
      }
      var granted = await _service.hasPermissions();
      if (_disposed) return;
      if (granted != true && requestPermission) {
        await _service.requestPermissions();
        if (_disposed) return;
        granted = await _service.hasPermissions();
        if (_disposed) return;
      }
      if (granted == false) {
        _publish(
          const HealthState(
            phase: HealthPhase.permission,
            message:
                'Permission not granted. Allow read access to steps, heart '
                'rate and sleep. If the prompt does not appear, open Health '
                'Connect → App permissions → Health Integration.',
          ),
        );
        return;
      }
      final data = await _service.read();
      _publish(
        HealthState(
          phase: data.isEmpty ? HealthPhase.empty : HealthPhase.ready,
          message: data.isEmpty
              ? _privateReadAccess
                    ? 'No data available or read access is not allowed. Apple Health hides read permission status. Review Health access and check the Health app.'
                    : 'No data available. Permissions are granted. Add records using '
                          'a connected health app or Health Connect Toolbox, then Refresh.'
              : _privateReadAccess
              ? 'Updated from Apple Health. Missing values may mean no records or read access is not allowed.'
              : 'Updated. Missing values mean no records in that time window.',
          data: data,
          canRequestPermission: _privateReadAccess,
        ),
      );
    } on HealthAuthorizationException {
      _publish(
        const HealthState(
          phase: HealthPhase.permission,
          message: 'Apple Health authorization could not complete. Check Health access and device restrictions, then try again.',
          canRequestPermission: true,
        ),
      );
    } catch (_) {
      // Native exceptions may contain sensitive data; never display or log them.
      _publish(
        HealthState(
          phase: HealthPhase.failure,
          message:
              'Unable to read $_provider. Check permissions and provider '
              'updates, then tap Refresh to retry.',
          canRequestPermission: _privateReadAccess,
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
