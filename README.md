# Health Integration

A Flutter application that displays read-only summaries from Android Health
Connect and Apple HealthKit, with bounded data processing and testable UI state.
Health data stays on the device; the app has no backend, account system,
network client, or app-managed persistence.

**Supported app targets: Android and iOS only.** Native read paths are implemented
for Health Connect and HealthKit. Synthetic tests exercise both contracts; actual
HealthKit access still requires physical-device verification. Web and desktop
targets are not included.

## Features

- Today's aggregated steps since local midnight.
- Latest heart-rate sample within the last 30 days, including its timestamp.
- Sleep interval duration over the last 24 hours, clipped to the window with
  overlaps merged. Android uses sleep sessions; iOS combines visible in-bed,
  asleep, awake, core/light, deep, and REM intervals. This includes recorded awake
  or in-bed time and is not an asleep-only total.
- Explicit authorization, refresh, loading, empty, unavailable, and retry states.
- Android permission rechecks before every read; all refreshes clear old values.
  On iOS, revocation is reflected through newly visible data or empty results.
- Privacy-aware Apple Health messages: read denial and empty data cannot be
  distinguished, so no false claim of granted read access is made.
- Synthetic unit, component integration, widget, and mobile device E2E suites.

The app reads existing records. It does not measure pulse, count steps with phone
sensors, track sleep, or write health data. Missing records are shown as
**No data available**. A recorded zero-step aggregate is distinguished from an
empty record store. A null aggregate remains unknown rather than being estimated
from potentially overlapping raw sources.

## Technology and architecture

Flutter 3.47.2 stable / Dart 3.13.2 is the inspected toolchain and the CI baseline.
The only runtime package beyond Flutter is
[`health` 13.3.2](https://pub.dev/packages/health/versions/13.3.2), retained through
`pubspec.lock`. Tests use Flutter SDK packages; no mocking or state management
package is added.

```text
HealthScreen → HealthController → HealthService → HealthSource → health plugin
  widgets      ChangeNotifier     repository /    native calls
               immutable state    processing
```

- `lib/main.dart`: Material 3 app and one scrollable screen with live status
  announcements. Widgets render state and forward actions.
- `lib/health_controller.dart`: availability, Android grant checks and unknown
  HealthKit read access,
  refresh transitions, safe error messages, duplicate-request protection, and
  disposal guards. Only successful reads expose values to the screen.
- `lib/health_service.dart`: bounded queries and validation, latest heart-rate
  selection, and sleep interval merging. An injectable clock fixes test windows.
- `lib/health_source.dart`: detects the native store, maps shared metrics to
  supported plugin types, and requests reads only. It calls the existing plugin
  channel for HealthKit availability because health 13.3.2 implements that native
  method without exposing a Dart wrapper.

The screen owns its default controller. An injected controller stays owned by its
caller. In-flight native calls cannot be canceled by this plugin boundary;
disposal ignores completions and prevents subsequent controller stages from starting.
There is no extra routing, DI container, domain layer, or background service.
Native exception bodies are neither displayed nor logged by application code.

## Platform requirements and permissions

### Android

Use Android 9/API 28+ with a usable Health Connect provider and Google Play
services. Android 14+ is recommended: Health Connect is integrated into the
system. On Android 9–13, install/update
[Health Connect](https://play.google.com/store/apps/details?id=com.google.android.apps.healthdata)
and complete initial setup in your personal profile.

The Android app retains minSdk 26 for the plugin; devices below the provider's
requirements show the unavailable state. Compile/target SDK and NDK follow the
pinned Flutter SDK defaults. Existing native tooling is AGP 9.1.0, Gradle 9.3.1,
and Java 17. Install the SDK/NDK components requested by Flutter using Android
Studio's SDK Manager.

| Permission | Purpose |
| --- | --- |
| `android.permission.health.READ_STEPS` | Native aggregated steps and the empty-store check |
| `android.permission.health.READ_HEART_RATE` | Heart-rate samples |
| `android.permission.health.READ_SLEEP` | Sleep sessions |

All three read grants are required before reading Android health data. A
partial grant is treated as denied. Launch and Refresh check existing grants;
**Grant read permissions** opens system authorization, then actual grants are
rechecked. Repeated denials may require enabling access in **Health Connect →
App permissions → Health Integration**. Returning from Settings does not
automatically refresh.

No write, background-read, extended-history, location, or activity-recognition
permissions are requested. The 30-day heart-rate lookup avoids a lifetime query.
The manifest retains provider visibility, a pre-Android-14 rationale activity,
and an Android-14+ permission-usage alias. `MainActivity` remains a
`FlutterFragmentActivity` for plugin permission callbacks. The native privacy
screen explains local-only use and how to revoke access.

See the [Health Connect setup documentation](https://developer.android.com/health-and-fitness/health-connect/get-started)
and [record types and permissions](https://developer.android.com/health-and-fitness/health-connect/data-types).

### iOS

The deployment target remains iOS 15.0. Building requires macOS, Xcode 26.1.1
or newer with its license accepted by the developer, and an installed simulator
runtime or configured device signing. Android/iOS identifiers and signing
settings are preserved; the HealthKit entitlement is linked to Runner.

`health` transitively depends on `device_info_plus` 13.3.0, which
[requires Xcode 26.1.1 or newer](https://pub.dev/packages/device_info_plus/versions/13.3.0).
CI selects the runner's installed Xcode 26.1.1 through the iOS job's
`DEVELOPER_DIR` and logs the selected Xcode and simulator SDK versions before
building. This avoids relying on the runner's default Xcode without changing
dependency versions or system-wide settings.

Runner declares `com.apple.developer.healthkit` in `Runner.entitlements`, linked
in Debug, Profile, and Release. `NSHealthShareUsageDescription` explains that
steps, heart rate, and sleep are read for an on-device summary. No writes,
background delivery, or clinical records are enabled.
`NSHealthUpdateUsageDescription` is omitted because no write access is requested.
The plugin receives only `HealthDataAccess.READ` for every requested type.

| Metric | Android type | HealthKit equivalent | Display window |
| --- | --- | --- | --- |
| Steps | `STEPS` / StepsRecord aggregate | `STEPS` / stepCount aggregate | Since local midnight |
| Heart rate | `HEART_RATE` | `HEART_RATE` / heartRate | Newest visible sample in 30 days |
| Sleep | `SLEEP_SESSION` | sleepAnalysis: in-bed, unspecified asleep, awake, core/light, deep, REM | Union of visible intervals in 24 hours |

HealthKit has no direct equivalent to an Android sleep-session record. In-bed
records and detailed stages may overlap, so the shared service merges all
intervals without double counting or filling gaps. Totals can differ between
platforms depending on what sources record. The plugin's iOS queries use a strict
start-date filter; sleep reads include an extra day's lookback so ordinary
crossing nights can be clipped to the display window. Records beginning more than
48 hours before Refresh can be omitted, even if they extend into that window.

Apple deliberately [hides read authorization status](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data).
The app can read previously authorized data on launch without displaying a system
prompt. Tap **Review Health access** to request access explicitly; this action
remains available because the app cannot inspect grants or distinguish revocation
from missing data. Completion of the authorization sheet does not prove any read
permission was granted. Denied/partial access can yield empty or partial results.
Incomplete requests, restrictions, unavailable services, and query exceptions
show guidance without exposing native response payloads.

For device signing, open Runner in Xcode, select an eligible development team,
and ensure the existing App ID and provisioning profile support HealthKit. The
capability is already configured in this project; do not change its bundle ID or
remove the entitlement to work around signing failures. Account/profile changes
are manual. Unsigned simulator CI does not validate device provisioning.

## Setup and execution

Install Flutter 3.47.2 and the native tools for your target, then run:

```sh
git clone https://github.com/gurhangure/health-integration.git
cd health-integration
flutter doctor
flutter pub get --enforce-lockfile
flutter devices
flutter run -d YOUR_MOBILE_DEVICE_ID
```

On a physical Android phone, enable USB debugging and accept the computer's
debugging prompt. Open Health Connect and complete setup, then launch the app,
tap **Grant read permissions**, enable the three types, and confirm. Values or
explicit empty states appear. Tap **Refresh** after changing data or permissions.
On iOS, tap **Review Health access** and use the Apple Health authorization sheet.
No API keys, OAuth setup, Google Cloud project, or backend configuration is needed.

For an Android debug APK or an unsigned iOS simulator build:

```sh
flutter build apk --debug
flutter build ios --simulator --debug --no-codesign
```

Run the iOS command on macOS only. Existing Android release settings still use a
debug signing key. Store distribution requires a separate signing and release
configuration; do not publish a debug-signed artifact as a production release.

### Display name and technical identifiers

The application display name is **Health Integration** on Android, iOS, and the
Flutter screen. The repository is
[`gurhangure/health-integration`](https://github.com/gurhangure/health-integration).
The existing technical identifiers are retained to preserve Dart imports, native
application identity, and signing configuration:

| Identifier | Value |
| --- | --- |
| Dart package and internal iOS bundle name | `health_connect_demo` |
| Android namespace/application ID | `com.example.health_connect_demo` |
| iOS bundle ID | `com.example.healthConnectDemo` |

The plugin-owned `flutter_health` method channel and generated references are
unchanged. The display name does not rename existing installed applications'
technical identities.

## Testing and CI

[Mobile CI](.github/workflows/ci.yml) runs on pushes, pull requests, and manual
dispatch. The workflow pins Flutter 3.47.2, enforces the application lockfile,
caches Flutter dependencies and Gradle, and uses separate quality, Android, and
iOS jobs. Its application build targets are exclusively Android and iOS.

| Level | Location | Coverage | Configured runner |
| --- | --- | --- | --- |
| Unit | `test/unit/` | Query windows, missing/zero data, invalid values, heart selection, overlapping sleep, controller transitions, retry, concurrent refresh and disposal | Ubuntu Flutter test runner |
| Component integration | `test/integration/` | Real controller + repository + synthetic native boundary; authorization, revocation, processing failures and disposal | Ubuntu Flutter test runner |
| Widget | `test/widget/` | Loading, disabled actions, permission interaction, values, revocation, empty/error/unavailable states, live semantics and large text | Ubuntu Flutter test runner |
| Device E2E | `integration_test/`, `test_driver/` | Authorize → read three metrics → refresh → revoke; also Apple Health privacy and authorization retry | API 35 Android emulator and available iPhone simulator on macOS 15 |

The quality job also runs `dart format --output=none --set-exit-if-changed .` and
`flutter analyze`. Android builds the normal debug APK; iOS builds the normal
unsigned simulator app before E2E runs.

The iOS job selects a simulator runtime matching the active Xcode simulator SDK
and bounds simulator boot to five minutes and the complete E2E command (including
its build and launch) to eight minutes. Each on-device test body has a two-minute
timeout. Verbose build output and driver results are saved; failed runs also
capture simulator state, a screenshot of the synthetic test app, process state,
and Runner logs. The `ios-e2e-diagnostics` artifact is retained for seven days.
The command's failure status is preserved when saving logs. Tests are not retried.

The iOS suite is built explicitly, installed, and launched paused using `simctl`.
`.github/scripts/ios_e2e.py` waits up to 90 seconds for the launched PID's VM
Service announcement in retained Runner logs, then attaches through Flutter's
supported `drive --use-existing-app` option. `test_driver/health_app_test.dart`
uses the SDK's `integrationDriver` to resume and report the same on-device tests,
including assertion failures, with a five-minute response deadline. CI terminates
the app after diagnostics are collected. Android keeps its existing `flutter test`
E2E command.

Every native launch-helper subprocess reports a flushed `START`/`END` stage,
its command, actual elapsed time, timeout limit, and exit status. Launch and VM
URI recovery retain partial stdout/stderr on failure, including timeouts;
installation and Driver output continue streaming into `flutter-driver.log`.
VM Service authentication URLs are redacted from helper-generated diagnostics.
Tests are not retried.

This launch workaround addresses the missed announcement observed in
[run 40580731543](https://github.com/gurhangure/health-integration/actions/runs/40580731543):
Runner emitted its VM Service URI and remained alive, while Flutter waited for
the announcement. Its live log reader started after launch was requested. The
blank app screenshot and absence of executed assertions support a pre-test
discovery stall consistent with the upstream race; the precise log-reader
readiness timing was not recorded.
The pinned Flutter 3.47.2 lacks the readiness wait introduced by
[upstream fix #193142](https://github.com/flutter/flutter/pull/193142) for
[issue #181771](https://github.com/flutter/flutter/issues/181771);
[issue #189059](https://github.com/flutter/flutter/issues/189059) was linked to
the same race. A direct switch to `flutter drive` would reuse that affected
launcher; attaching to an already launched app avoids it. SDK source is unchanged.
Replace this workaround when a verified stable release includes the fix.

Device tests launch the actual Flutter app with a synthetic `HealthSource`, a
fixed clock, the real repository, and the real controller. On iOS an additional
fixture journey exercises HealthKit authorization privacy, overlapping Apple sleep
categories, hidden denial/revocation, and authorization retry. Component tests
exercise the real source mapping through a deterministic plugin fake and mocked
availability channel. No test uses personal health records, live
Health Connect, or external services. Fixtures are only imported by tests and
are not enabled in the production entry point.

The synthetic suites do **not** verify the native health plugin's channel
serialization, Android's system permission dialog, real provider queries,
Settings revocation, or signing/store distribution. Those need the separate
physical-device follow-up below. Synthetic E2E does not verify actual HealthKit
authorization, store queries, or device provisioning.

For explicitly requested local verification, deterministic suites and Android E2E
use these commands; iOS CI uses the launch-and-attach flow described above:

```sh
flutter test test/unit
flutter test test/integration
flutter test test/widget
flutter test integration_test/health_app_test.dart -d YOUR_ANDROID_DEVICE_ID
```

**Verification snapshot:** at portfolio review,
[HealthKit feature run 40593997488](https://github.com/gurhangure/health-integration/actions/runs/40593997488)
had passed formatting, static analysis, unit, component integration, and widget
tests, plus the Android build/E2E and iOS production simulator build. The iOS job
was still running with E2E pending; its final result was **not verified**. This
snapshot does not establish results for subsequent branding changes. Consult
[Actions](https://github.com/gurhangure/health-integration/actions) for the run
matching the current commit. Automated tests and native builds were not executed
locally during the portfolio review. Physical-device checks remain separate.

## Physical-device follow-up with synthetic records

For a visible Android result, use Google's
[Health Connect Toolbox](https://developer.android.com/health-and-fitness/health-connect/test/health-connect-toolbox):

1. Obtain its APK from the official page and install it on a dedicated test
   device/profile. Grant its read/write permissions for the relevant types.
2. Insert 123 steps over a short interval entirely within today, a 72 bpm heart
   sample a few minutes ago, and a sleep session from three hours ago to one hour
   ago. With no other records, this app should display 123, 72 bpm, and 2 h 0 min.
3. Refresh in this app. Existing records can change the results. Remove synthetic
   records through Toolbox/Health Connect when finished.

As a separate manual acceptance pass, check full/partial denial, authorization,
empty data, refresh, Settings revocation, provider unavailability, and the native
privacy link. Do not remove system Health Connect packages to force an error.
These steps are instructions, not a claim that device verification has occurred.

## Apple Health physical-device follow-up

Use a dedicated test device and synthetic records only. Configure signing as
above, launch the app, and tap **Review Health access**. Check the requested types
are steps, heart rate, and sleep with no write permissions. Confirm visible values
after enabling reads. For controlled values, add a small step entry, a heart-rate
sample, and a bounded sleep entry through Apple's Health app or an external test
tool; this app never writes those records. Existing records, source aggregation,
and sync can change totals.

Deny all reads and Refresh: expect the neutral empty/access message rather than a
claim that authorization was granted. Allow only some types and check the partial
summary. Revoke access in Health's app/data-access settings and Refresh: prior
values must clear or update to what remains visible. Test authorization
cancellation and available device restrictions, retry, empty stores, sleep
overlap/clipping, large text, and accessibility announcements. No result from
these manual checks is claimed here. The Health app's own sync settings are
independent of this app.

## Screenshots

No verified screenshots are included yet. After device validation, capture the
permission, synthetic-results, and empty states using only synthetic records.
Avoid real health data or personal account details in portfolio images.
