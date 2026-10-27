import 'package:integration_test/integration_test_driver.dart';

/// Reports the unchanged on-device suite through Flutter's existing-app driver.
Future<void> main() => integrationDriver(timeout: const Duration(minutes: 5));
