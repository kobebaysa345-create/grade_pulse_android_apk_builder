@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo ==============================================================
echo Grade Pulse - Flutter project setup
echo ==============================================================

if not exist "pubspec.yaml" (
  echo ERROR: pubspec.yaml was not found. Open this script from the grade_pulse folder.
  pause
  exit /b 1
)
if not exist "lib\main.dart" (
  echo ERROR: lib\main.dart was not found.
  pause
  exit /b 1
)
where flutter >nul 2>nul
if errorlevel 1 (
  echo ERROR: Flutter was not found in PATH.
  echo Install the Flutter SDK, add its bin folder to PATH, reopen this terminal, and try again.
  pause
  exit /b 1
)

set "BACKUP_DIR=%TEMP%\grade_pulse_backup_%RANDOM%_%RANDOM%"
mkdir "%BACKUP_DIR%" >nul 2>nul
xcopy "lib" "%BACKUP_DIR%\lib" /E /I /H /Y >nul
if exist "test" xcopy "test" "%BACKUP_DIR%\test" /E /I /H /Y >nul
copy /Y "pubspec.yaml" "%BACKUP_DIR%\pubspec.yaml" >nul

echo Creating missing Android, Web, and Windows Flutter platform files...
call flutter create --platforms=android,web,windows --project-name grade_pulse --no-pub .
set "CREATE_EXIT=%ERRORLEVEL%"
if not "%CREATE_EXIT%"=="0" goto :restore_failed

rem Restore the app's source, test, and dependency manifest in case the template changed them.
if exist "lib" rmdir /s /q "lib"
xcopy "%BACKUP_DIR%\lib" "lib" /E /I /H /Y >nul
if exist "%BACKUP_DIR%\test" (
  if exist "test" rmdir /s /q "test"
  xcopy "%BACKUP_DIR%\test" "test" /E /I /H /Y >nul
)
copy /Y "%BACKUP_DIR%\pubspec.yaml" "pubspec.yaml" >nul

echo Getting Dart and Flutter dependencies...
call flutter pub get
set "PUB_EXIT=%ERRORLEVEL%"
rmdir /s /q "%BACKUP_DIR%" >nul 2>nul
if not "%PUB_EXIT%"=="0" goto :pub_failed

echo.
echo Setup complete. You can now run:
echo   flutter run
 echo.
echo For a browser launch, use:
echo   flutter run -d chrome
 echo.
pause
exit /b 0

:restore_failed
echo ERROR: Flutter could not generate the platform folders. Restoring your original app files...
if exist "lib" rmdir /s /q "lib"
if exist "%BACKUP_DIR%\lib" xcopy "%BACKUP_DIR%\lib" "lib" /E /I /H /Y >nul
if exist "%BACKUP_DIR%\test" (
  if exist "test" rmdir /s /q "test"
  xcopy "%BACKUP_DIR%\test" "test" /E /I /H /Y >nul
)
if exist "%BACKUP_DIR%\pubspec.yaml" copy /Y "%BACKUP_DIR%\pubspec.yaml" "pubspec.yaml" >nul
rmdir /s /q "%BACKUP_DIR%" >nul 2>nul
pause
exit /b %CREATE_EXIT%

:pub_failed
echo Platform files were created, but flutter pub get failed. Check your internet connection and Flutter/Dart SDK installation, then run flutter pub get manually.
pause
exit /b %PUB_EXIT%
