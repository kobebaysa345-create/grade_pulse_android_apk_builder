# Grade Pulse — Flutter + Dart

Grade Pulse is a personal school grade tracker built with Flutter and Dart. The `lib/` directory contains the application source code. The project manifest (`pubspec.yaml`) declares Flutter and the packages used by the app.

## Requirements

- Flutter SDK (3.27 or newer recommended for the APIs used by this source)
- Dart SDK bundled with Flutter
- Internet access for the first dependency download
- Android Studio / an Android SDK and an emulator or connected device for Android runs; Chrome for web runs

Confirm Flutter is installed:

```bash
flutter --version
flutter doctor
```

## First-time setup on Windows

1. Extract the ZIP file.
2. Open the **`grade_pulse` root folder** in Antigravity or VS Code. The root is the folder containing `pubspec.yaml`; do not open only `lib/` or `main.dart`.
3. Double-click `SETUP_FLUTTER.bat`. It creates the standard Android, Web, and Windows platform scaffolding using your installed Flutter SDK while preserving the existing `lib/` source, `test/` folder, and `pubspec.yaml`.
4. When setup finishes, run from the same folder:

```powershell
flutter pub get
flutter run
```

To run in Chrome after the Web platform is generated:

```powershell
flutter run -d chrome
```

To run on a connected Android device or emulator, start the emulator first and then use `flutter devices` to confirm Flutter can see it.

## First-time setup on macOS or Linux

From the project root, with Flutter installed:

```bash
flutter create --platforms=android,web --project-name grade_pulse .
flutter pub get
flutter run
```

`flutter create` generates the missing platform folders. If you use a different Flutter target, replace the platforms list with the targets supported by your computer and SDK.

## Run checks

```bash
flutter analyze
flutter test
```

## Academics, calculator and insights

- **Academics → Records**: add, rename, edit and delete terms, subjects (code, title, units 1–30) and assessments (title, category Quiz / Assignment / Exam / Laboratory / Project / Other, score, max score). Scores cannot be negative or above the max (extra credit is not supported). Duplicate term names and duplicate subject codes in a term are rejected. Averages and term results update instantly; deletes offer **Undo**; a status line shows *Saving… / All changes saved / Not saved (Retry)*.
- **Academics → Insights**: cumulative and current-term results, units, subjects, a target-progress bar, subject comparison bars, a term trend line (needs two graded terms), strongest/lowest subject, and assessments needing attention (below 75%, above max, subjects with no scores, subjects below your target). Premade records are treated as ordinary saved records once loaded.
- **Calculator**: enter Quizzes, Recitation, Group Activities, Self-Check, Unit Test 1, Unit Test 2, and Term Test scores to calculate the overall weighted grade. Class Activities contribute 30% (7.5% each), Unit Tests 40% (20% each), and the Term Test 30%. Inputs accept scores from 0–100, update the result automatically when complete, and are saved with the account along with a component breakdown.
- **Settings → Grading**: grade conversion tables (4.0 GPA and TUP / PLM) and your target average. The built-in tables are generic defaults, not official school rules; edit them to match your school.

## Calendar, reminders, and study groups

- **Calendar** retains Day, Week, Month, and Year views, previous/next navigation, a Today shortcut, selected-date event details, date markers, and an event-category filter. Selecting a date updates the event list below the calendar.
- **Reminders and tasks** support add/edit/delete, completion, subject code, category, description, priority, date and time, overdue/upcoming status, and category/status filters. Changes are saved to the signed-in account.
- **Study groups** support search, group details (course, description, members, and discussion notes), linked tasks, and scheduled study sessions. Group tasks and sessions are stored once as reminders carrying a `groupId`, so they appear on the calendar without duplicating the same event record.
- **Navigation and profile** provide an upper-left drawer, five bottom tabs (Academics, Groups, Calendar, Calculator, Me), and a profile page with editable local account name/email plus saved student metadata. Grade Calculator remains available from the Academics dashboard and drawer. The drawer also opens the Antigravity data workspace.
- **JSON compatibility** is now schema version 4. Versions 1, 2 and 3 migrate with safe defaults. The version 4 `profile` object contains only non-sensitive school/program/year-level metadata; authentication identity, emails, passwords, hashes, salts and session data remain outside JSON.

## Data management

- **Settings → Data → Premade** loads the pre-configured dataset from `assets/data/grade_pulse_data.json`. Review it before merging with existing records or replacing the account data. Once applied, the records are saved to the signed-in account and can be customized like other records.
- **Antigravity → JSON Management** exposes the current account data as an editable, validated document. Use **Review & apply changes** to inspect the edit and choose Merge or Replace before it is saved. **Structure Preview** summarizes the data currently in the editor.
- The existing data codec, bundled asset path, and data-transfer validation remain in place; file import/export services are retained in code but are not shown as data-menu actions.

Invalid, incomplete, corrupted or newer-schema data is rejected with an explanation, and nothing is changed. Data is always saved to the signed-in account only. See [`docs/JSON_DATA.md`](docs/JSON_DATA.md) for the file format, versioning and migration rules.

Platform notes: Android, iOS, Windows, Linux and web work with the default setup. On **macOS**, add the *User Selected File → Read/Write* capability (`com.apple.security.files.user-selected.read-write`) to `macos/Runner/DebugProfile.entitlements` and `Release.entitlements` after `flutter create`.

## Notes about accounts and storage

The current authentication is a **local demonstration**, not a production account service. Accounts, session, app settings, and per-user records are stored on the device through `shared_preferences`; clearing app data removes that data. The code comments and `SETUP.md` describe the limitations and the future path to a real backend such as Firebase Authentication.

---

## Reactive State and Architecture (Riverpod)

Grade Pulse now uses `flutter_riverpod` as the reactive application-state layer while preserving its existing local account and data formats.

### Key folders

- `lib/models/`: academic terms, courses, assessments, reminders, groups, settings, profile, and user data models.
- `lib/providers/`: session, user-data, repository, and derived analytics providers.
- `lib/repositories/`: the `UserDataRepository` storage boundary and its local implementation.
- `lib/views/`: the five primary navigation view boundaries and the main shell.
- `lib/screens/`: supporting screen/form/dialog implementations retained during the incremental migration.
- `lib/services/`: authentication, versioned SharedPreferences storage, grading calculations, JSON codec, and file transfer.

### State flow

`MainScreen` loads the signed-in account through `UserDataNotifier`. Shared academic data is exposed through `userDataProvider`; a successful change publishes a new state wrapper immediately, while persistence is queued through the repository. The academics, groups, calendar, calculator, and profile view boundaries watch the shared provider. Derived grade analytics are available through `academicAnalyticsProvider` and summary counts through `userDataSummaryProvider`.

The user-data repository continues to use the existing per-account SharedPreferences keys and schema migration logic. JSON import/export remains a separate file-based backup/restore mechanism, and the bundled `assets/data/grade_pulse_data.json` remains a read-only preset source.

### Development checks

Run these commands from `grade_pulse/` in an environment with a compatible Flutter SDK:

```bash
flutter pub get
dart format lib test
flutter analyze
flutter test
```

The refactor was prepared in an environment without the Flutter/Dart command-line SDK, so those commands must be run locally before submitting the project. The architecture migration is incremental: the existing tab feature builders still live in `views/main_shell_view.dart` and can be moved into their individual view files in a future pass without changing the provider/repository contracts.
