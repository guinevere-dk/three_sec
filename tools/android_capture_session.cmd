@echo off
setlocal enabledelayedexpansion

if not exist logs mkdir logs

for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set TS=%%i

set ADB_EXE=adb
where adb >nul 2>nul
if errorlevel 1 (
  if exist "%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" (
    set ADB_EXE=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
  )
)
set DEVICE_ID=

set FULL_LOG=logs\session_%TS%_full.log
set ERR_LOG=logs\session_%TS%_errors.log
set APP_LOG=logs\session_%TS%_appsignals.log
set APP_FULL_LOG=logs\session_%TS%_appfull.log
set DIAG_LOG=logs\session_%TS%_diagnostics.log
set PKG_NAME=com.dk.three_sec

if /i "%~1"=="--auto-start" set AUTO_START_APP=1
if /i "%~1"=="--no-auto-start" set AUTO_START_APP=0
if "%AUTO_START_APP%"=="" set AUTO_START_APP=0
echo [DIAG] AUTO_START_APP=%AUTO_START_APP% (0=수동, 1=자동)

if "%KAKAO_NATIVE_APP_KEY%"=="" (
  echo [DIAG] 환경변수 KAKAO_NATIVE_APP_KEY가 비어 있습니다.
  echo [DIAG] 기본 테스트 실행을 진행하려면 아래와 같이 실행하세요.
  echo        set KAKAO_NATIVE_APP_KEY=발급받은_네이티브앱키
  echo        tools\android_capture_session.cmd
  echo [DIAG] 경고: --dart-define 미지정 시 카카오 로그인이 실패할 수 있습니다.
) else (
  echo [DIAG] KAKAO_NATIVE_APP_KEY 확인됨
)

if "%SOCIAL_AUTH_EXCHANGE_URL%"=="" (
  echo [DIAG] 환경변수 SOCIAL_AUTH_EXCHANGE_URL가 비어 있습니다.
  echo [DIAG] 기본 테스트 실행을 진행하려면 아래와 같이 실행하세요.
  echo        set SOCIAL_AUTH_EXCHANGE_URL=https://your-domain.example.com/social/exchange
) else (
  echo [DIAG] SOCIAL_AUTH_EXCHANGE_URL 확인됨
)

echo [1/6] adb device check...
"%ADB_EXE%" devices
if errorlevel 1 (
  echo [ERROR] adb 실행 실패. Android SDK platform-tools 경로를 확인하세요.
  goto :eof
)

for /f "skip=1 tokens=1,2" %%A in ('"%ADB_EXE%" devices') do (
  if "%%B"=="device" (
    if not defined DEVICE_ID set DEVICE_ID=%%A
  )
)

echo [2/6] clear logcat buffer...
"%ADB_EXE%" logcat -c

if "%DEVICE_ID%"=="" (
  echo [ERROR] Android 디바이스 ID를 찾지 못했습니다. ^(adb devices 기준^)
  echo [DIAG] ADB_EXE=%ADB_EXE%
  goto :eof
)

echo [DIAG] ADB_EXE=%ADB_EXE%
echo [DIAG] RAW_DEVICE_ID=%DEVICE_ID%
echo      device id: %DEVICE_ID%

set KAKAO_DART_DEFINE=--dart-define=KAKAO_NATIVE_APP_KEY=%KAKAO_NATIVE_APP_KEY%
if not "%SOCIAL_AUTH_EXCHANGE_URL%"=="" (
  set KAKAO_DART_DEFINE=%KAKAO_DART_DEFINE% --dart-define=SOCIAL_AUTH_EXCHANGE_URL=%SOCIAL_AUTH_EXCHANGE_URL%
)

echo [3/6] start app in separate terminal...
if "%AUTO_START_APP%"=="1" (
  echo [DIAG] AUTO_START_APP=1: flutter run 실행 (앱 재설치/재기동 가능)
  echo [DIAG] flutter run command: flutter run %KAKAO_DART_DEFINE%
  start "flutter_run_session" cmd /k "flutter run %KAKAO_DART_DEFINE%"
) else (
  echo [DIAG] AUTO_START_APP=0: 자동 실행 생략(현재 실행 중인 앱을 수동으로 실행)
)


echo [4/6] perform test scenario on device, then return here.
echo      when finished, press ENTER to dump logcat buffer.
pause >nul

echo [5/6] dump logcat buffer to file...
"%ADB_EXE%" -s %DEVICE_ID% logcat -d -v threadtime > "%FULL_LOG%"
echo [DIAG] extract package-scoped logs for %PKG_NAME% from full log (PID 고정 없이 전 구간 수집)...
findstr /I /C:"%PKG_NAME%" "%FULL_LOG%" > "%APP_FULL_LOG%"

echo [6/6] extract key signals...
findstr /I /R /C:" [EWF] " /C:"FATAL EXCEPTION" /C:"ANR" /C:"PlatformException" /C:"Unhandled Exception" /C:"OutOfMemoryError" /C:"NoSuchMethodError" /C:"MissingPluginException" /C:"TimeoutException" "%APP_FULL_LOG%" > "%ERR_LOG%"
findstr /I /C:"flutter :" /C:"[Capture]" /C:"[VideoManager]" /C:"[CloudService]" /C:"[IAPService]" /C:"[AuthService]" /C:"[EditScreen]" "%APP_FULL_LOG%" > "%APP_LOG%"

for /f %%C in ('find /C /V "" ^< "%FULL_LOG%"') do set FULL_COUNT=%%C
for /f %%C in ('find /C /V "" ^< "%APP_FULL_LOG%"') do set APP_COUNT=%%C
for /f %%C in ('findstr /I /R /C:" [EWF] " "%APP_FULL_LOG%" ^| find /C /V ""') do set APP_EWF_COUNT=%%C
for /f %%C in ('findstr /I /C:"%PKG_NAME%" "%FULL_LOG%" ^| find /C /V ""') do set PKG_REF_COUNT=%%C

(
  echo [DIAG] DEVICE_ID=%DEVICE_ID%
  echo [DIAG] PKG_NAME=%PKG_NAME%
  echo [DIAG] FULL_LOG_LINES=%FULL_COUNT%
  echo [DIAG] APP_LOG_LINES=%APP_COUNT%
  echo [DIAG] APP_EWF_LINES=%APP_EWF_COUNT%
  echo [DIAG] PKG_REF_IN_FULL=%PKG_REF_COUNT%
) > "%DIAG_LOG%"

taskkill /FI "WINDOWTITLE eq flutter_run_session" /T /F >nul 2>nul

echo ---------------------------------------------
echo Session logs created:
echo   %FULL_LOG%
echo   %ERR_LOG%
echo   %APP_LOG%
echo   %APP_FULL_LOG%
echo   %DIAG_LOG%
echo ---------------------------------------------

endlocal



