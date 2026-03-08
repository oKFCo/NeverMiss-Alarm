# NeverMiss Alarm

Cross-platform alarm app focused on Android and Windows.

## Product direction

- Behaves like a normal alarm app first (create/edit/toggle/delete alarms).
- Supports secure remote alarm triggers for Verint workflow integration.
- Avoids using ADB as a production transport.

## Current implementation

- Alarm domain model + local JSON persistence.
- Polished tabbed UX:
  - `Alarms` tab (create/edit/delete/toggle/test-now)
  - `History` tab (activity timeline + clear)
  - `Settings` tab (global snooze, auto-stop timeout, 24h format)
- Per-alarm snooze override editable in alarm editor.
- Next-alarm and upcoming alarms cards.
- Android native scheduling via local notifications:
  - exact allow-while-idle scheduling
  - recurring day-of-week alarms
  - auto-sync of schedules when alarms change
  - permission request action in settings
- Windows background scheduling via Task Scheduler:
  - creates per-alarm scheduled tasks (`schtasks`)
  - launches app with `--trigger-alarm-id=<id>` at alarm time
  - one-time alarms auto-disable after triggered launch
- Windows active alarm attention:
  - looping bundled alarm sound (`assets/sounds/alarm_loop.wav`) while alarm is active
  - restores/focuses app window and keeps it on top during active ring
- Active ringing overlay with:
  - dismiss
  - configurable snooze
  - configurable auto-stop timeout
- `Disable all alarms` quick action.
- Security primitives for remote trigger verification:
  - HMAC-SHA256 signature validation
  - request timestamp skew check
  - nonce replay protection
- Remote trigger handler that maps verified remote events into local alarms.
- Remote payload parsing layer (`Map<String,dynamic>` -> typed trigger).
- Local fail-safe foundation:
  - persistent paired devices registry
  - persistent source->target route rules
  - timeout-trigger hook from alarm engine
  - real local LAN receiver endpoint (`/failsafe/trigger`) with signed payload verification
  - local LAN discovery via UDP broadcast (`Discover on LAN`)
  - route test dispatch over HTTP on local network
  - interactive `Fail-safe` tab for setup/pair/test/logs (no CLI required)
- Windows Verint Schedule Bridge (extension-free):
  - local loopback endpoint: `http://127.0.0.1:38941/verint/schedule`
  - imports schedule payload into `[Verint]` alarms
  - replaces previous browser extension dependency for schedule ingest
  - includes bookmarklet generation in Settings tab

## Alarm scope note

This phase completes app-level alarm behavior and UX flow.

Windows scheduling note:
- Best reliability is with packaged runner executable builds.
- During `flutter run` debug sessions, Task Scheduler launch behavior can vary by environment.

## Remote trigger payload (draft v1)

```json
{
  "event_type": "panic",
  "status_text": "Door forced",
  "scheduled_at_ms": 1730000000000,
  "timeout_at_ms": 1730000600000,
  "timestamp_ms": 1730000001000,
  "nonce": "d1f6b9...",
  "signature": "hex_hmac_sha256"
}
```

Signature canonical string:

```txt
event_type|status_text|scheduled_at_ms|timeout_at_ms|timestamp_ms|nonce
```

## Recommended architecture

1. Use local Windows Verint Schedule Bridge (no browser extension).
2. Backend API as source of truth and security boundary.
3. Android receives signed trigger events via FCM data messages.
4. Windows app communicates with backend for schedule/status/history.
5. Keep ADB bridge only for local/dev fallback.

## Run

```bash
flutter pub get
flutter run -d windows
```

Android:

```bash
flutter run -d android
```

## Beta deployment checklist

1. Set a release version/build in `pubspec.yaml`.
2. Configure Android signing:
   - Copy `android/key.properties.example` to `android/key.properties`.
   - Fill `storeFile`, `storePassword`, `keyAlias`, and `keyPassword` with real release keystore values.
3. Build beta artifacts:
   - Android App Bundle: `flutter build appbundle --release`
   - Android APK: `flutter build apk --release`
4. iOS/TestFlight (on macOS with Xcode):
   - `flutter build ipa --release`
5. Run validation before publishing:
   - `flutter analyze`
   - `flutter test`

## GitHub Release automation

This repo includes an automated release workflow at `.github/workflows/release.yml`.

- Trigger: push a tag that starts with `v` (for example `v1.0.1`).
- Output artifacts:
  - `NeverMissAlarm-android-<tag>.apk`
  - `NeverMissAlarm-windows-<tag>.zip`
- Release: artifacts are attached to a GitHub Release automatically.

Android signing in GitHub Actions:

- Add repository secrets:
  - `ANDROID_KEYSTORE_BASE64` (base64 of your `.keystore` file)
  - `ANDROID_STORE_PASSWORD`
  - `ANDROID_KEY_ALIAS`
  - `ANDROID_KEY_PASSWORD`
- If these are missing, workflow falls back to a debug APK.

Local helper to generate release signing material:

```powershell
powershell -ExecutionPolicy Bypass -File tools/setup_android_signing.ps1
```

This creates:
- `android/release.keystore`
- `android/key.properties`
- `android/github_actions_secrets.txt` (copy values into GitHub secrets)
- `android/release_signing_credentials.txt` (backup locally, do not share)

Create and push a release tag:

```bash
git tag v1.0.1
git push origin v1.0.1
```

