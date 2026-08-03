@echo off
echo ===================================================
echo PC Control Agent - Automated Installer
echo ===================================================

:: Request Admin Privileges if not running as Admin
NET SESSION >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    echo Requesting Administrator privileges...
    powershell -Command "Start-Process -FilePath '%0' -Verb RunAs"
    exit /b
)

echo.
echo [1/4] Creating installation directory at C:\Program Files\PC-Agent...
mkdir "C:\Program Files\PC-Agent" 2>nul
copy /Y "PC-Agent.exe" "C:\Program Files\PC-Agent\" >nul
copy /Y "*.dll" "C:\Program Files\PC-Agent\" 2>nul
copy /Y "*.json" "C:\Program Files\PC-Agent\" 2>nul

echo [2/4] Creating configuration directory at C:\ProgramData\PC-Agent...
mkdir "C:\ProgramData\PC-Agent" 2>nul
if not exist "C:\ProgramData\PC-Agent\config.json" (
    copy /Y "config.example.json" "C:\ProgramData\PC-Agent\config.json" >nul
    echo NOTE: Created new config.json. Please edit C:\ProgramData\PC-Agent\config.json!
) else (
    echo NOTE: config.json already exists, skipping overwrite.
)

echo [3/4] Stopping any existing service...
sc stop "PC-Agent" >nul 2>&1
timeout /t 2 /nobreak >nul

echo [4/4] Installing and starting the Windows Service...
sc delete "PC-Agent" >nul 2>&1
timeout /t 2 /nobreak >nul
sc create "PC-Agent" binPath= "C:\Program Files\PC-Agent\PC-Agent.exe" start= auto
sc start "PC-Agent"

echo.
echo ===================================================
echo DONE! The agent is now running 24/7 in the background.
echo Check the Web Dashboard to see if it is online.
echo ===================================================
pause
