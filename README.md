# Health Connect Demo

A small Flutter portfolio project that demonstrates read-only Android Health
Connect access, bounded data processing, permission handling, and testable UI
state. Health data stays on the device; the app has no backend, account system,
network client, or app-managed persistence.

**Supported app targets: Android and iOS only.** Health Connect reading is
implemented on Android. The iOS app displays an explicit unavailable message;
Apple HealthKit reading is not implemented and no HealthKit permissions or
capabilities are configured. Web and desktop targets are not included.

## Features

- Today's aggregated steps since local midnight.
- Latest heart-rate sample within the last 30 days, including its timestamp.
- Sleep-session duration over the last 24 hours, with intervals clipped to the
  window and overlaps merged. This includes awake time within sessions; it is
  not a total of asleep stages.
- Explicit authorization, refresh, loading, empty, unavailable, and retry states.
- Permission rechecks before every read; revocation clears previous values.
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
- `lib/health_controller.dart`: availability, all-or-nothing read grants,
  refresh transitions, safe error messages, duplicate-request protection, and
  disposal guards. Only successful reads expose values to the screen.
- `lib/health_service.dart`: bounded queries and validation, latest heart-rate
  selection, and sleep interval merging. An injectable clock fixes test windows.
- `lib/health_source.dart`: a small native plugin boundary replaced by synthetic
  fixtures in tests. Production calls use the unchanged native health APIs.

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

All three read grants are required for this intentionally small screen. A
partial grant is treated as denied. Launch and Refresh check existing grants;
**Grant read permissions** opens system authorization, then actual grants are
rechecked. Repeated denials may require enabling access in **Health Connect →
App permissions → Health Connect Demo**. Returning from Settings does not
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

The existing deployment target is iOS 15.0. Building requires macOS, Xcode 26.1.1
or newer with its license accepted by the developer, and an installed iOS
simulator runtime or configured device signing. The iOS shell and its
unavailable state are covered by the configured simulator CI job. HealthKit
entitlements, usage descriptions, native authorization, and health queries are
outside the current implementation. Android/iOS identifiers and signing settings
have been preserved.

`health` transitively depends on `device_info_plus` 13.3.0, which
[requires Xcode 26.1.1 or newer](https://pub.dev/packages/device_info_plus/versions/13.3.0).
CI selects the runner's installed Xcode 26.1.1 through the iOS job's
`DEVELOPER_DIR` and logs the selected Xcode and simulator SDK versions before
building. This avoids relying on the runner's default Xcode without changing
dependency versions or system-wide settings.

## Setup and execution

Install Flutter 3.47.2 and the native tools for your target, then run:

```sh
flutter doctor
flutter pub get --enforce-lockfile
flutter devices
flutter run -d YOUR_MOBILE_DEVICE_ID
```

On a physical Android phone, enable USB debugging and accept the computer's
debugging prompt. Open Health Connect and complete setup, then launch the app,
tap **Grant read permissions**, enable the three types, and confirm. Values or
explicit empty states appear. Tap **Refresh** after changing data or permissions.
No API keys, OAuth setup, Google Cloud project, or backend configuration is needed.

For an Android debug APK or an unsigned iOS simulator build:

```sh
flutter build apk --debug
flutter build ios --simulator --debug --no-codesign
```

Run the iOS command on macOS only. Existing Android release settings still use a
debug signing key; this is a portfolio/debug project, not store distribution
configuration. Do not publish that artifact as a production release.

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
| Device E2E | `integration_test/` | Authorize → read three metrics → refresh → revoke; also normal iOS launch | API 35 Android emulator and available iPhone simulator on macOS 15 |

The quality job also runs `dart format --output=none --set-exit-if-changed .` and
`flutter analyze`. Android builds the normal debug APK; iOS builds the normal
unsigned simulator app before E2E runs.

Device tests launch the actual Flutter app with a synthetic `HealthSource`, a
fixed clock, the real repository, and the real controller. On iOS this fixture
journey explicitly simulates Android provider availability; a second test checks
the normal iOS unavailable screen. No test uses personal health records, live
Health Connect, or external services. Fixtures are only imported by tests and
are not enabled in the production entry point.

The synthetic suites do **not** verify the native health plugin's channel
serialization, Android's system permission dialog, real provider queries,
Settings revocation, or signing/store distribution. Those need the separate
physical-device follow-up below. iOS HealthKit is not part of the suite.

For explicitly requested local verification, the same commands used by CI are:

```sh
flutter test test/unit
flutter test test/integration
flutter test test/widget
flutter test integration_test/health_app_test.dart -d YOUR_MOBILE_DEVICE_ID
```

**Verification status:** dependency resolution and local static analysis completed
successfully during this update. Automated tests and native builds were not run
locally. Check the repository's Actions tab for execution results; every test level,
Android/iOS build, and CI result remains **unverified** until observed. Local Apple developer tools
also report an unaccepted Xcode license; no license or system settings were
changed. Please verify CI after publication and schedule physical-device checks
separately.

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

## Screenshots

No verified screenshots are included yet. After device validation, capture the
permission, synthetic-results, and empty states using only synthetic records.
Avoid real health data or personal account details in portfolio images.
