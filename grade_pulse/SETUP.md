# Grade Pulse — Flutter + Dart setup

This folder is a Flutter/Dart application source project. `pubspec.yaml` is the actual Flutter project manifest. The app source is in `lib/`.

## Windows (recommended: Antigravity or VS Code)

1. Install the Flutter SDK and ensure `flutter --version` works in a new terminal.
2. Extract the ZIP.
3. Open the **`grade_pulse` root folder** (the folder that contains `pubspec.yaml`). Do not open only `lib/` or `main.dart`.
4. Double-click `SETUP_FLUTTER.bat`. It runs `flutter create` to generate platform folders supported by the local Flutter SDK, then restores the existing app code and dependencies and runs `flutter pub get`.
5. In a terminal opened at the project root, run:

```powershell
flutter pub get
flutter devices
flutter run
```

To launch in Chrome:

```powershell
flutter run -d chrome
```

## macOS / Linux

With Flutter installed, open a terminal at the project root and run:

```bash
flutter create --platforms=android,web --project-name grade_pulse .
flutter pub get
flutter run
```

## Verify the project

```bash
flutter analyze
flutter test
```

A local installation of the Flutter SDK is required to generate platform runners and compile/run the application. This ZIP includes the app code and the required `pubspec.yaml`; the setup script generates platform folders that match your installed Flutter version.

## Data and authentication note

The current auth layer is a **local demonstration**, not a production authentication service. Accounts, session, theme settings, and per-user records are stored on the device using `shared_preferences`. Clearing app data removes this information. The source code comments describe limitations and how to replace local authentication with a real backend in a later stage.
