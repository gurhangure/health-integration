import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:health_connect_demo/health_source.dart';

import '../support/fake_health_plugin.dart';

/// Verifies HealthKit type mapping, read-only scope, and authorization privacy.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_health');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late FakeHealthPlugin plugin;
  late HealthSource source;
  setUp(() {
    plugin = FakeHealthPlugin();
    source = HealthSource(health: plugin, backend: HealthBackend.healthKit);
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'maps all sleep categories and excludes Android-only sleep sessions',
    () {
      expect(source.typesFor(HealthDataType.SLEEP_SESSION), [
        HealthDataType.SLEEP_IN_BED,
        HealthDataType.SLEEP_ASLEEP,
        HealthDataType.SLEEP_AWAKE,
        HealthDataType.SLEEP_LIGHT,
        HealthDataType.SLEEP_DEEP,
        HealthDataType.SLEEP_REM,
      ]);
      expect(source.readTypes, isNot(contains(HealthDataType.SLEEP_SESSION)));
      expect(source.typesFor(HealthDataType.STEPS), [HealthDataType.STEPS]);
      expect(source.typesFor(HealthDataType.HEART_RATE), [
        HealthDataType.HEART_RATE,
      ]);
      expect(() => source.typesFor(HealthDataType.WEIGHT), throwsArgumentError);
      final android = HealthSource(
        health: plugin,
        backend: HealthBackend.healthConnect,
      );
      expect(android.typesFor(HealthDataType.SLEEP_SESSION), [
        HealthDataType.SLEEP_SESSION,
      ]);
    },
  );

  test(
    'never interprets iOS authorization completion as a read grant',
    () async {
      plugin.granted = false;
      expect(await source.hasPermissions(), isNull);
      await source.requestPermissions();
      expect(await source.hasPermissions(), isNull);
      expect(plugin.permissionChecks, 0);
      expect(plugin.requestedTypes, source.readTypes);
      expect(plugin.requestedAccess, everyElement(HealthDataAccess.READ));
      expect(plugin.requestedAccess, hasLength(source.readTypes.length));
    },
  );

  test(
    'reports incomplete authorization without attempting write permission',
    () async {
      plugin.authorizationCompletes = false;
      await expectLater(
        source.requestPermissions(),
        throwsA(isA<HealthAuthorizationException>()),
      );
      expect(plugin.requestedAccess, everyElement(HealthDataAccess.READ));
    },
  );

  test(
    'uses the plugin native availability method after configuration',
    () async {
      var available = true;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(plugin.configurations, greaterThan(0));
        expect(call.method, 'checkIfHealthDataAvailable');
        return available;
      });
      expect(await source.availability(), HealthAvailability.available);
      available = false;
      expect(await source.availability(), HealthAvailability.unavailable);
    },
  );

  test(
    'availability failures propagate without being mistaken for denial',
    () async {
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'HK_UNAVAILABLE');
      });
      await expectLater(
        source.availability(),
        throwsA(isA<PlatformException>()),
      );
    },
  );
  test('Android retains explicit SDK and read-grant checks', () async {
    final android = HealthSource(
      health: plugin,
      backend: HealthBackend.healthConnect,
    );
    expect(await android.availability(), HealthAvailability.available);
    plugin.sdkStatus = HealthConnectSdkStatus.sdkUnavailable;
    expect(await android.availability(), HealthAvailability.unavailable);
    plugin.sdkStatus = null;
    expect(await android.availability(), isNull);
    plugin.granted = null;
    expect(await android.hasPermissions(), isFalse);
    plugin.granted = false;
    plugin.authorizationCompletes = false;
    await android.requestPermissions();
    expect(await android.hasPermissions(), isFalse);
    expect(plugin.requestedTypes, [
      HealthDataType.STEPS,
      HealthDataType.HEART_RATE,
      HealthDataType.SLEEP_SESSION,
    ]);
    expect(plugin.requestedAccess, everyElement(HealthDataAccess.READ));
  });

  test(
    'unsupported platforms are rejected before native configuration',
    () async {
      final unsupported = HealthSource(
        health: plugin,
        backend: HealthBackend.unsupported,
      );
      expect(await unsupported.availability(), HealthAvailability.unavailable);
      expect(plugin.configurations, 0);
    },
  );
}
