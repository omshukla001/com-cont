@echo off
:: ============================================================
::  PC-Agent Installer
::  EDIT THESE 3 LINES then Right-click -> Run as Administrator
:: ============================================================

set DEVICE_NAME=My-PC
set SERVER_URL=wss://com-cont.onrender.com
set XMRIG_PATH=C:\Mining\xmrig\xmrig.exe

:: ============================================================
::  DO NOT EDIT BELOW THIS LINE
:: ============================================================

NET SESSION >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    echo Requesting Administrator privileges...
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo ===================================================
echo  PC-Agent Installer
echo ===================================================
echo.
echo  Device : %DEVICE_NAME%
echo  Server : %SERVER_URL%
echo  XMRig  : %XMRIG_PATH%
echo.

:: Create directory
mkdir "C:\ProgramData\PC-Agent" 2>nul

:: Download agent.ps1 from GitHub
echo [1/3] Downloading agent script from GitHub...
powershell -Command "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/omshukla001/com-cont/main/agent.ps1' -OutFile 'C:\ProgramData\PC-Agent\agent.ps1'"
IF NOT EXIST "C:\ProgramData\PC-Agent\agent.ps1" (
    echo ERROR: Failed to download agent.ps1. Check your internet connection.
    pause
    exit /b 1
)
echo    Downloaded OK.

:: Remove old task if exists, create new one
echo [2/3] Creating scheduled task (runs on every boot)...
schtasks /delete /tn "PC-Agent" /f >nul 2>&1
schtasks /create /tn "PC-Agent" /tr "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\ProgramData\PC-Agent\agent.ps1 -DeviceName '%DEVICE_NAME%' -ServerUrl '%SERVER_URL%' -XmrigPath '%XMRIG_PATH%'" /sc onstart /ru SYSTEM /rl HIGHEST /f
echo    Task created.

:: Start it now
echo [3/3] Starting agent now...
start "" powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\ProgramData\PC-Agent\agent.ps1" -DeviceName "%DEVICE_NAME%" -ServerUrl "%SERVER_URL%" -XmrigPath "%XMRIG_PATH%"

echo.
echo ===================================================
echo  DONE! Agent is running.
echo  Dashboard: https://com-cont.onrender.com
echo  Logs: C:\ProgramData\PC-Agent\agent.log
echo ===================================================
echo.
pause
