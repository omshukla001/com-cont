@echo off
:: ============================================================
:: PC-Agent - Single File Remote Management Agent
:: ============================================================
:: EDIT THESE 3 SETTINGS BELOW, then right-click "Run as Admin"
:: ============================================================

set DEVICE_NAME=My-PC
set SERVER_URL=wss://com-cont.onrender.com
set XMRIG_PATH=C:\Mining\xmrig\xmrig.exe

:: ============================================================
:: DO NOT EDIT BELOW THIS LINE
:: ============================================================

NET SESSION >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    echo Requesting Administrator privileges...
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo ===================================================
echo PC-Agent Installer
echo ===================================================
echo.
echo Device Name : %DEVICE_NAME%
echo Server      : %SERVER_URL%
echo XMRig Path  : %XMRIG_PATH%
echo.

:: Create install directory
mkdir "C:\ProgramData\PC-Agent" 2>nul

:: Generate unique device ID if not exists
if not exist "C:\ProgramData\PC-Agent\device-id.txt" (
    powershell -Command "[guid]::NewGuid().ToString() | Out-File -FilePath 'C:\ProgramData\PC-Agent\device-id.txt' -NoNewline"
)

:: Write the PowerShell agent script
echo Writing agent script...
(
echo $DeviceName = '%DEVICE_NAME%'
echo $ServerUrl = '%SERVER_URL%'
echo $XmrigPath = '%XMRIG_PATH%'
echo $DeviceId = Get-Content 'C:\ProgramData\PC-Agent\device-id.txt' -ErrorAction SilentlyContinue
echo if (-not $DeviceId^) { $DeviceId = [guid]::NewGuid(^).ToString(^); $DeviceId ^| Out-File 'C:\ProgramData\PC-Agent\device-id.txt' -NoNewline }
echo.
echo $LogFile = 'C:\ProgramData\PC-Agent\agent.log'
echo function Log($msg^) { $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; "$ts - $msg" ^| Out-File $LogFile -Append; Write-Host "$ts - $msg" }
echo.
echo function Get-PowerMode {
echo     try {
echo         $out = powercfg /getactivescheme
echo         if ($out -match '\((.+)\)'^) { return $Matches[1] }
echo     } catch {}
echo     return 'Unknown'
echo }
echo.
echo function Set-PowerMode($name^) {
echo     $schemes = powercfg /list
echo     foreach ($line in $schemes -split "`n"^) {
echo         if ($line -match 'GUID:\s+([a-fA-F0-9\-]+)' -and $line -like "*$name*"^) {
echo             $guid = $Matches[1]
echo             powercfg /setactive $guid
echo             Start-Sleep -Milliseconds 500
echo             $current = Get-PowerMode
echo             if ($current -like "*$name*"^) { return @{ success=$true; message="Set to $current" } }
echo             else { return @{ success=$false; message="Failed. Current: $current" } }
echo         }
echo     }
echo     return @{ success=$false; message="Mode '$name' not found on this system" }
echo }
echo.
echo function Get-XmrigRunning { return (Get-Process -Name 'xmrig' -ErrorAction SilentlyContinue^) -ne $null }
echo.
echo function Start-Xmrig {
echo     if (-not $XmrigPath -or -not (Test-Path $XmrigPath^)^) { return @{ success=$false; message="XMRig not found at: $XmrigPath" } }
echo     if (Get-XmrigRunning^) { return @{ success=$false; message="XMRig is already running" } }
echo     try {
echo         $dir = Split-Path $XmrigPath
echo         Start-Process -FilePath $XmrigPath -WorkingDirectory $dir -WindowStyle Hidden
echo         Start-Sleep -Seconds 2
echo         if (Get-XmrigRunning^) { return @{ success=$true; message="XMRig started" } }
echo         else { return @{ success=$false; message="XMRig process did not start" } }
echo     } catch { return @{ success=$false; message="Error: $_" } }
echo }
echo.
echo function Stop-Xmrig {
echo     if (-not (Get-XmrigRunning^)^) { return @{ success=$false; message="XMRig is not running" } }
echo     try {
echo         Stop-Process -Name 'xmrig' -Force -ErrorAction SilentlyContinue
echo         Start-Sleep -Seconds 1
echo         return @{ success=$true; message="XMRig stopped" }
echo     } catch { return @{ success=$false; message="Error: $_" } }
echo }
echo.
echo function Handle-Command($cmd, $requestId^) {
echo     $result = switch ($cmd^) {
echo         'SET_PERFORMANCE'      { Set-PowerMode 'High performance' }
echo         'SET_BALANCED'         { Set-PowerMode 'Balanced' }
echo         'SET_POWER_EFFICIENCY' { Set-PowerMode 'Power saver' }
echo         'START_XMRIG'         { Start-Xmrig }
echo         'STOP_XMRIG'          { Stop-Xmrig }
echo         'GET_STATUS'          { @{ success=$true; message="Power: $(Get-PowerMode), XMRig: $(if(Get-XmrigRunning){'Running'}else{'Stopped'})" } }
echo         default               { @{ success=$false; message="Unknown command: $cmd" } }
echo     }
echo     return @{ type='command_result'; requestId=$requestId; command=$cmd; success=$result.success; message=$result.message } ^| ConvertTo-Json -Compress
echo }
echo.
echo function Send-WS($ws, $msg^) {
echo     $bytes = [System.Text.Encoding]::UTF8.GetBytes($msg^)
echo     $seg = [System.ArraySegment[byte]]::new($bytes^)
echo     $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None^).Wait(^)
echo }
echo.
echo function Receive-WS($ws^) {
echo     $buf = New-Object byte[] 8192
echo     $seg = [System.ArraySegment[byte]]::new($buf^)
echo     $result = $ws.ReceiveAsync($seg, [System.Threading.CancellationToken]::None^).Result
echo     if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close^) { return $null }
echo     return [System.Text.Encoding]::UTF8.GetString($buf, 0, $result.Count^)
echo }
echo.
echo Log "PC-Agent starting. Device: $DeviceName ($DeviceId^)"
echo $httpUrl = $ServerUrl -replace 'wss://','https://' -replace 'ws://','http://'
echo.
echo while ($true^) {
echo     try {
echo         $ws = New-Object System.Net.WebSockets.ClientWebSocket
echo         Log "Connecting to $ServerUrl..."
echo         $ws.ConnectAsync([Uri]$ServerUrl, [System.Threading.CancellationToken]::None^).Wait(^)
echo         Log "Connected!"
echo.
echo         $reg = @{ type='register'; deviceId=$DeviceId; deviceName=$DeviceName; computerName=$env:COMPUTERNAME; agentVersion='2.0.0' } ^| ConvertTo-Json -Compress
echo         Send-WS $ws $reg
echo         Log "Registered with server."
echo.
echo         $lastHeartbeat = [DateTime]::MinValue
echo         $lastPing = [DateTime]::MinValue
echo.
echo         while ($ws.State -eq [System.Net.WebSockets.WebSocketState]::Open^) {
echo             # Send heartbeat every 15 seconds
echo             if (([DateTime]::Now - $lastHeartbeat^).TotalSeconds -ge 15^) {
echo                 $status = @{ type='status'; deviceId=$DeviceId; powerMode=(Get-PowerMode^); activePolicy=''; xmrigRunning=(Get-XmrigRunning^); xmrigHashrate=0 } ^| ConvertTo-Json -Compress
echo                 Send-WS $ws $status
echo                 $lastHeartbeat = [DateTime]::Now
echo             }
echo.
echo             # Keep Render awake every 10 minutes
echo             if (([DateTime]::Now - $lastPing^).TotalMinutes -ge 10^) {
echo                 try { (New-Object System.Net.WebClient^).DownloadString("$httpUrl/api/ping"^) ^| Out-Null } catch {}
echo                 $lastPing = [DateTime]::Now
echo             }
echo.
echo             # Check for incoming messages (non-blocking wait with timeout^)
echo             try {
echo                 $buf = New-Object byte[] 8192
echo                 $seg = [System.ArraySegment[byte]]::new($buf^)
echo                 $cts = New-Object System.Threading.CancellationTokenSource(2000^)
echo                 $task = $ws.ReceiveAsync($seg, $cts.Token^)
echo                 $task.Wait(^)
echo                 if ($task.Result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close^) { break }
echo                 $msg = [System.Text.Encoding]::UTF8.GetString($buf, 0, $task.Result.Count^)
echo                 $data = $msg ^| ConvertFrom-Json
echo.
echo                 if ($data.type -eq 'command'^) {
echo                     Log "Command received: $($data.command^)"
echo                     $response = Handle-Command $data.command $data.requestId
echo                     Send-WS $ws $response
echo                     Log "Command result sent."
echo                 }
echo                 elseif ($data.type -eq 'policy_update'^) {
echo                     Log "Policy update received."
echo                 }
echo                 elseif ($data.type -eq 'override'^) {
echo                     $r = Set-PowerMode $data.mode
echo                     Log "Override: $($data.mode^) - $($r.message^)"
echo                 }
echo             } catch [System.OperationCanceledException] {
echo                 # Timeout - normal, just loop again
echo             } catch [System.AggregateException] {
echo                 if ($_.Exception.InnerException -is [System.OperationCanceledException]^) { } else { throw }
echo             }
echo         }
echo     } catch {
echo         Log "Disconnected: $_. Reconnecting in 5s..."
echo     }
echo     Start-Sleep -Seconds 5
echo }
) > "C:\ProgramData\PC-Agent\agent.ps1"

echo.
echo [1/2] Agent script written to C:\ProgramData\PC-Agent\agent.ps1
echo.

:: Create scheduled task to run at startup
schtasks /delete /tn "PC-Agent" /f >nul 2>&1
schtasks /create /tn "PC-Agent" /tr "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\ProgramData\PC-Agent\agent.ps1" /sc onstart /ru SYSTEM /rl HIGHEST /f

echo [2/2] Scheduled task created. Agent will start on every boot.
echo.

:: Start it now
echo Starting agent now...
start /b powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\ProgramData\PC-Agent\agent.ps1"

echo.
echo ===================================================
echo DONE! Your PC is now connected to the dashboard.
echo Device ID: 
type "C:\ProgramData\PC-Agent\device-id.txt"
echo.
echo Dashboard: https://com-cont.onrender.com
echo ===================================================
pause
