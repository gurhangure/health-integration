import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:health_connect_demo/health_controller.dart';

import '../support/fake_health_source.dart';

/// Exercises the real controller/repository boundary with synthetic native data.
void main() {
  test('denial, authorization, processing, and revocation cooperate', () async {
    final source = populatedSource();
    final controller = fixtureController(source);
    addTearDown(controller.dispose);

    await controller.refresh();
    expect(controller.state.phase, HealthPhase.permission);
    expect(source.queries, isEmpty);
    expect(source.requests, 0);

    await controller.refresh(requestPermission: true);
    expect(controller.state.phase, HealthPhase.ready);
    expect(source.permissionChecks, 3);
    expect(controller.state.data?.steps, 123);
    expect(controller.state.data?.heartRate, 72);
    expect(controller.state.data?.sleep, const Duration(hours: 2));

    source.granted = false;
    await controller.refresh();
    expect(controller.state.phase, HealthPhase.permission);
    expect(controller.state.data, isNull);
    expect(source.totalReads, 1);
  });

  test(
    'invalid plugin records become a recoverable presentation error',
    () async {
      final source = populatedSource()..granted = true;
      source.data[HealthDataType.HEART_RATE] = [
        point(HealthDataType.HEART_RATE, fixtureNow, value: double.nan),
      ];
      final controller = fixtureController(source);
      addTearDown(controller.dispose);
      await controller.refresh();
      expect(controller.state.phase, HealthPhase.failure);
      expect(controller.state.data, isNull);
      source.data[HealthDataType.HEART_RATE] = [];
      await controller.refresh();
      expect(controller.state.phase, HealthPhase.ready);
      expect(controller.state.data?.heartRate, isNull);
    },
  );

  test(
    'disposal during availability prevents subsequent native operations',
    () async {
      final source = populatedSource()..availabilityGate = Completer<void>();
      final controller = fixtureController(source);
      final refreshing = controller.refresh(requestPermission: true);
      controller.dispose();
      source.availabilityGate!.complete();
      await refreshing;
      expect(source.permissionChecks, 0);
      expect(source.requests, 0);
      expect(source.totalReads, 0);
    },
  );
}
