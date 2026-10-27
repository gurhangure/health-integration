import 'dart:async';

import 'package:flutter/material.dart';

import 'health_controller.dart';

/// Starts the read-only Health Integration application.
void main() => runApp(const HealthApp());

/// Supplies the app's Material theme and single health screen.
class HealthApp extends StatelessWidget {
  /// An injected controller remains owned and disposed by its caller.
  const HealthApp({super.key, this.controller});

  final HealthController? controller;

  /// Builds the app shell shared by normal runs and device E2E tests.
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Health Integration',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
    home: HealthScreen(controller: controller),
  );
}

/// Displays read status, health metrics, and explicit permission/refresh actions.
class HealthScreen extends StatefulWidget {
  /// An injected controller remains owned and disposed by its caller.
  const HealthScreen({super.key, this.controller});

  final HealthController? controller;

  /// Creates the lifecycle owner for this screen's controller.
  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

/// Owns the default controller and forwards user actions to it.
class _HealthScreenState extends State<HealthScreen> {
  late final HealthController _controller;

  /// Starts an availability check without requesting permissions on launch.
  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? HealthController();
    unawaited(_controller.refresh());
  }

  /// Releases only the controller created by this screen.
  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  /// Presents a metric with its query window and empty-state description.
  Widget _value(String title, String value, String detail) => Card(
    child: ListTile(
      title: Text(title),
      subtitle: Text('$value\n$detail'),
      isThreeLine: true,
    ),
  );

  /// Rebuilds from controller state without accessing the native plugin.
  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: _controller, builder: _buildContent);

  /// Renders mutually exclusive loading, permission, empty, and result states.
  Widget _buildContent(BuildContext context, Widget? child) {
    const empty = 'No data available';
    final state = _controller.state;
    final loading = state.phase == HealthPhase.loading;
    final data = state.data;
    final sleep = data?.sleep;
    final heartTime = data?.heartTime;
    return Scaffold(
      appBar: AppBar(title: const Text('Health Integration')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Read-only access • Health data stays on this device.'),
            const SizedBox(height: 16),
            if (loading) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(state.message, key: const ValueKey('status')),
            ),
            const SizedBox(height: 16),
            _value(
              'Steps',
              data == null ? '—' : data.steps?.toString() ?? empty,
              'Today, since local midnight',
            ),
            _value(
              'Heart rate',
              data == null
                  ? '—'
                  : data.heartRate == null
                  ? empty
                  : '${data.heartRate} bpm',
              heartTime == null
                  ? 'Latest sample within the last 30 days'
                  : 'Sample: ${heartTime.toLocal().toString().split('.').first}',
            ),
            _value(
              'Sleep',
              data == null
                  ? '—'
                  : sleep == null
                  ? empty
                  : '${sleep.inHours} h ${sleep.inMinutes.remainder(60)} min',
              _controller.sleepDetail,
            ),
            const SizedBox(height: 16),
            if (state.phase == HealthPhase.permission ||
                state.canRequestPermission)
              FilledButton(
                onPressed: () => _controller.refresh(requestPermission: true),
                child: Text(_controller.permissionActionLabel),
              ),
            OutlinedButton.icon(
              onPressed: loading ? null : () => _controller.refresh(),
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }
}
