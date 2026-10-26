# Build and download the Grade Pulse Android app

This project archive contains Flutter source code, not an installable Android APK. The GitHub Actions workflow at `.github/workflows/build-android-apk.yml` generates the Android platform files and attempts to build the APK in GitHub Actions.

## Build the APK

1. Extract this project folder on your computer.
2. Publish the *contents of this `grade_pulse` folder* to a GitHub repository. The `.github` folder must be included. You may use GitHub Desktop or Git.
3. Open the repository on GitHub and select **Actions**.
4. Select **Build Grade Pulse Android APK**. A push to the `main` or `master` branch starts it automatically. You can also choose **Run workflow**.
5. Open the latest run. If it succeeds, scroll to **Artifacts** and download **Grade-Pulse-Android-APK**.
6. Extract the artifact ZIP. It contains `app-release.apk`.
7. Transfer `app-release.apk` to your Android phone using Google Drive, USB, or Quick Share.
8. On the phone, tap the APK and follow Android's installation prompts. Only install APKs from sources you trust.

## If the workflow fails

Open the failed job and inspect the first failing step. A green check appears only if formatting, analysis, tests, and the APK build all pass. Fix the errors and push the changes to run it again.

## Notes

- This creates an Android APK for testing/sideloading; it does not publish the app to the Play Store.
- You do not need to make the GitHub repository public solely to use GitHub Actions. A private repository can also work, subject to your GitHub account's Actions limits.
- Because Android platform files are generated during the workflow, test/build issues may still need fixing before an APK artifact is produced.
