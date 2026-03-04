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
set APP_PID=

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

echo [3/6] start app in separate terminal...
start "flutter_run_session" cmd /k "flutter run -d %DEVICE_ID%"

echo [4/6] perform test scenario on device, then return here.
echo      when finished, press ENTER to dump logcat buffer.
pause >nul

echo [DIAG] resolve app pid for %PKG_NAME% ...
for /f %%P in ('"%ADB_EXE%" -s %DEVICE_ID% shell pidof -s %PKG_NAME% 2^>nul') do set APP_PID=%%P
if defined APP_PID (
  echo [DIAG] APP_PID=%APP_PID%
) else (
  echo [WARN] APP_PID 조회 실패. 앱 전용 로그는 fallback 방식으로 생성됩니다.
)

echo [5/6] dump logcat buffer to file...
"%ADB_EXE%" -s %DEVICE_ID% logcat -d -v threadtime > "%FULL_LOG%"

if defined APP_PID (
  "%ADB_EXE%" -s %DEVICE_ID% logcat -d --pid=%APP_PID% -v threadtime > "%APP_FULL_LOG%"
) else (
  copy /Y "%FULL_LOG%" "%APP_FULL_LOG%" >nul
)

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
  echo [DIAG] APP_PID=%APP_PID%
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

