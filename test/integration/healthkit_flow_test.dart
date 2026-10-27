import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:health_connect_demo/health_controller.dart';
import 'package:health_connect_demo/health_service.dart';
import 'package:health_connect_demo/health_source.dart';

import '../support/fake_health_plugin.dart';
import '../support/fake_health_source.dart';

/// Exercises real iOS mapping and shared processing with a fake native plugin.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_health');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late FakeHealthPlugin plugin;
  late HealthController controller;
  var available = true;
  setUp(() {
    available = true;
    messenger.setMockMethodCallHandler(channel, (_) async => available);
    plugin = FakeHealthPlugin();
    controller = HealthController(
      service: HealthService(
        source: HealthSource(health: plugin, backend: HealthBackend.healthKit),
        now: () => fixtureNow,
      ),
    );
  });
  tearDown(() {
    controller.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'reads all three metrics and merges overlapping Apple categories',
    () async {
      plugin.data[HealthDataType.HEART_RATE] = [
        point(
          HealthDataType.HEART_RATE,
          fixtureNow,
          value: 78,
          platform: HealthPlatformType.appleHealth,
        ),
      ];
      plugin.data[HealthDataType.SLEEP_IN_BED] = [
        point(
          HealthDataType.SLEEP_IN_BED,
          fixtureNow.subtract(const Duration(hours: 3)),
          end: fixtureNow.subtract(const Duration(hours: 1)),
          platform: HealthPlatformType.appleHealth,
        ),
      ];
      plugin.data[HealthDataType.SLEEP_LIGHT] = [
        point(
          HealthDataType.SLEEP_LIGHT,
          fixtureNow.subtract(const Duration(hours: 2)),
          end: fixtureNow.subtract(const Duration(hours: 1)),
          platform: HealthPlatformType.appleHealth,
        ),
      ];
      await controller.refresh(requestPermission: true);
      expect(controller.state.phase, HealthPhase.ready);
      expect(controller.state.data?.steps, 123);
      expect(controller.state.data?.heartRate, 78);
      expect(controller.state.data?.sleep, const Duration(hours: 2));
      expect(plugin.requestedAccess, everyElement(HealthDataAccess.READ));
      expect(plugin.queries.last, contains(HealthDataType.SLEEP_REM));
      expect(controller.state.canRequestPermission, isTrue);
      expect(plugin.permissionChecks, 0);
    },
  );

  test(
    'hidden denial and revocation appear as unknown empty data, not a grant',
    () async {
      await controller.refresh();
      expect(controller.state.data?.steps, 123);
      plugin.steps = 0;
      plugin.data.clear();
      await controller.refresh();
      expect(controller.state.phase, HealthPhase.empty);
      expect(controller.state.data?.steps, isNull);
      expect(controller.state.message, contains('read access is not allowed'));
      expect(
        controller.state.message,
        isNot(contains('Permissions are granted')),
      );
      expect(controller.state.canRequestPermission, isTrue);
    },
  );

  test(
    'includes a crossing Apple sleep record and clips it to the display window',
    () async {
      plugin.data[HealthDataType.SLEEP_IN_BED] = [
        point(
          HealthDataType.SLEEP_IN_BED,
          fixtureNow.subtract(const Duration(hours: 30)),
          end: fixtureNow.subtract(const Duration(hours: 22)),
          platform: HealthPlatformType.appleHealth,
        ),
      ];
      await controller.refresh();
      expect(controller.state.data?.sleep, const Duration(hours: 2));
      expect(plugin.windows.last, (
        fixtureNow.subtract(const Duration(hours: 48)),
        fixtureNow,
      ));
    },
  );

  test(
    'supports sleep stages even when no in-bed envelope was recorded',
    () async {
      plugin.data[HealthDataType.SLEEP_DEEP] = [
        point(
          HealthDataType.SLEEP_DEEP,
          fixtureNow.subtract(const Duration(hours: 2)),
          end: fixtureNow,
          platform: HealthPlatformType.appleHealth,
        ),
      ];
      await controller.refresh();
      expect(controller.state.data?.sleep, const Duration(hours: 2));
    },
  );

  test(
    'incomplete or restricted authorization is actionable and recoverable',
    () async {
      plugin.authorizationCompletes = false;
      await controller.refresh(requestPermission: true);
      expect(controller.state.phase, HealthPhase.permission);
      expect(controller.state.data, isNull);
      expect(plugin.queries, isEmpty);
      plugin.authorizationCompletes = true;
      await controller.refresh(requestPermission: true);
      expect(controller.state.phase, HealthPhase.ready);
    },
  );

  test(
    'native and validation errors clear values and never expose payloads',
    () async {
      await controller.refresh();
      plugin.failure = PlatformException(
        code: 'HK_QUERY_ERROR',
        message: 'private record',
      );
      await controller.refresh();
      expect(controller.state.phase, HealthPhase.failure);
      expect(controller.state.data, isNull);
      expect(controller.state.message, contains('Apple Health'));
      expect(controller.state.message, isNot(contains('private record')));
      plugin.failure = null;
      plugin.steps = -1;
      await controller.refresh();
      expect(controller.state.phase, HealthPhase.failure);
    },
  );

  test(
    'unavailable HealthKit never queries records or requests permissions',
    () async {
      available = false;
      await controller.refresh(requestPermission: true);
      expect(controller.state.phase, HealthPhase.unavailable);
      expect(plugin.queries, isEmpty);
      expect(plugin.requestedTypes, isNull);
    },
  );
}
