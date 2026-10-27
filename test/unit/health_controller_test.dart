import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_connect_demo/health_controller.dart';
import 'package:health_connect_demo/health_source.dart';
import 'package:health_connect_demo/health_service.dart';

/// Isolates presentation transitions from record processing and native plugins.
class StubHealthService extends Fake implements HealthService {
  /// Selects provider-specific presentation while keeping the service isolated.
  @override
  HealthBackend backend = HealthBackend.healthConnect;

  HealthAvailability? status = HealthAvailability.available;
  bool granted = true;
  bool grantOnRequest = true;
  int reads = 0;
  int requests = 0;
  int checks = 0;
  Object? failure;
  Completer<HealthSnapshot>? pending;
  HealthSnapshot snapshot = const HealthSnapshot(steps: 123);

  /// Supplies controlled availability, including unknown provider failures.
  @override
  Future<HealthAvailability?> availability() async => status;

  /// Counts grant checks to verify authorization is rechecked after the prompt.
  @override
  Future<bool> hasPermissions() async {
    checks++;
    return granted;
  }

  /// Simulates a full or incomplete grant.
  @override
  Future<void> requestPermissions() async {
    requests++;
    granted = grantOnRequest;
  }

  /// Supplies a pending read or a controlled failure without native access.
  @override
  Future<HealthSnapshot> read() async {
    reads++;
    if (failure != null) throw failure!;
    return pending == null ? snapshot : await pending!.future;
  }
}

/// Tests isolated controller transitions, recovery, concurrency, and disposal.
void main() {
  late StubHealthService service;
  late HealthController controller;
  setUp(() {
    service = StubHealthService();
    controller = HealthController(service: service);
  });
  tearDown(() => controller.dispose());

  test(
    'publishes loading then results and clears values on revocation',
    () async {
      final phases = <HealthPhase>[];
      controller.addListener(() => phases.add(controller.state.phase));
      await controller.refresh();
      expect(phases, [HealthPhase.loading, HealthPhase.ready]);
      expect(controller.state.data?.steps, 123);
      service.granted = false;
      await controller.refresh();
      expect(controller.state.phase, HealthPhase.permission);
      expect(controller.state.data, isNull);
      expect(service.reads, 1);
      expect(service.requests, 0);
    },
  );

  test('rechecks grants and performs no read after a partial grant', () async {
    service.granted = false;
    service.grantOnRequest = false;
    await controller.refresh(requestPermission: true);
    expect(service.requests, 1);
    expect(service.checks, 2);
    expect(service.reads, 0);
    expect(controller.state.phase, HealthPhase.permission);
  });

  test(
    'reads after full grant and distinguishes authorized empty data',
    () async {
      service.granted = false;
      service.snapshot = const HealthSnapshot();
      await controller.refresh(requestPermission: true);
      expect(controller.state.phase, HealthPhase.empty);
      expect(service.reads, 1);
    },
  );

  test('unknown and unavailable providers never trigger a read', () async {
    service.status = null;
    await controller.refresh();
    expect(controller.state.phase, HealthPhase.failure);
    service.status = HealthAvailability.unavailable;
    await controller.refresh(requestPermission: true);
    expect(controller.state.phase, HealthPhase.unavailable);
    expect(service.checks, 0);
    expect(service.requests, 0);
    expect(service.reads, 0);
  });

  test('sanitizes exceptions and permits a successful retry', () async {
    service.failure = StateError('sensitive native response');
    await controller.refresh();
    expect(controller.state.phase, HealthPhase.failure);
    expect(controller.state.message, isNot(contains('sensitive')));
    expect(controller.state.data, isNull);
    service.failure = null;
    await controller.refresh();
    expect(controller.state.phase, HealthPhase.ready);
  });

  test('deduplicates concurrent refreshes', () async {
    service.pending = Completer<HealthSnapshot>();
    final first = controller.refresh();
    // Drain the immediate availability and permission futures deterministically.
    await Future<void>.delayed(Duration.zero);
    expect(service.reads, 1);
    await controller.refresh();
    service.pending!.complete(const HealthSnapshot(steps: 10));
    await first;
    expect(service.reads, 1);
  });

  test('ignores a read completion after disposal', () async {
    final disposable = HealthController(service: service);
    service.pending = Completer<HealthSnapshot>();
    var notifications = 0;
    disposable.addListener(() => notifications++);
    final reading = disposable.refresh();
    await Future<void>.delayed(Duration.zero);
    disposable.dispose();
    service.pending!.complete(const HealthSnapshot(steps: 99));
    await reading;
    expect(notifications, 1);
  });

  test('unsupported platforms never request health data', () async {
    service.backend = HealthBackend.unsupported;
    service.status = HealthAvailability.unavailable;
    await controller.refresh(requestPermission: true);
    expect(controller.state.phase, HealthPhase.unavailable);
    expect(controller.state.message, contains('Android and iOS only'));
    expect(service.checks, 0);
    expect(service.requests, 0);
    expect(service.reads, 0);
  });
}
