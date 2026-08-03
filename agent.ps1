param(
    [string]$DeviceName = "My-PC",
    [string]$ServerUrl = "wss://com-cont.onrender.com",
    [string]$XmrigPath = "C:\Mining\xmrig\xmrig.exe"
)

# ============================================================
# PC-Agent - Single File PowerShell Agent
# ============================================================

$DataDir = "C:\ProgramData\PC-Agent"
if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Path $DataDir -Force | Out-Null }

$IdFile = Join-Path $DataDir "device-id.txt"
if (Test-Path $IdFile) {
    $DeviceId = Get-Content $IdFile -Raw
    $DeviceId = $DeviceId.Trim()
} else {
    $DeviceId = [guid]::NewGuid().ToString()
    $DeviceId | Out-File $IdFile -NoNewline
}

$LogFile = Join-Path $DataDir "agent.log"
function Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts - $msg" | Out-File $LogFile -Append
    Write-Host "$ts - $msg"
}

# Ensure all required power plans exist on this PC
function Ensure-PowerPlans {
    $schemes = powercfg /list 2>&1 | Out-String
    if ($schemes -notmatch "High performance") {
        Log "Creating 'High performance' power plan..."
        powercfg /duplicatescheme 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>&1 | Out-Null
    }
    if ($schemes -notmatch "Power saver") {
        Log "Creating 'Power saver' power plan..."
        powercfg /duplicatescheme a1841308-3541-4fab-bc81-f71556f20b4a 2>&1 | Out-Null
    }
}
Ensure-PowerPlans

# Use standard Windows Power Plans (Base Plans)
# These change the actual hardware state (CPU clocks, etc) even if the Windows 11 Settings app doesn't reflect it
$GUID_HIGH_PERFORMANCE = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
$GUID_BALANCED         = "381b4222-f694-41f0-9685-ff5bb260df2e"
$GUID_POWER_SAVER      = "a1841308-3541-4fab-bc81-f71556f20b4a"

function Get-PowerMode {
    try {
        $out = powercfg /getactivescheme 2>&1 | Out-String
        if ($out -match '\((.+)\)') { return $Matches[1].Trim() }
    } catch {}
    return "Unknown"
}

function Set-PowerMode($modeName) {
    $guid = $GUID_BALANCED
    $friendlyName = "Balanced"

    if ($modeName -match "erformance") {
        $guid = $GUID_HIGH_PERFORMANCE
        $friendlyName = "High performance"
    } elseif ($modeName -match "aver" -or $modeName -match "fficiency") {
        $guid = $GUID_POWER_SAVER
        $friendlyName = "Power saver"
    }
    
    try { 
        powercfg /setactive $guid 2>&1 | Out-Null 
    } catch {
        return @{ success = $false; message = "Failed to set $friendlyName : $_" }
    }

    Start-Sleep -Milliseconds 500
    $current = Get-PowerMode
    Log "powercfg /setactive -> $current"
    return @{ success = $true; message = "Set to $current" }
}

function Get-XmrigRunning {
    return $null -ne (Get-Process -Name "xmrig" -ErrorAction SilentlyContinue)
}

function Start-Xmrig {
    if (-not $XmrigPath -or -not (Test-Path $XmrigPath)) {
        return @{ success = $false; message = "XMRig not found at: $XmrigPath" }
    }
    if (Get-XmrigRunning) {
        return @{ success = $false; message = "XMRig is already running" }
    }
    try {
        $dir = Split-Path $XmrigPath
        Start-Process -FilePath $XmrigPath -WorkingDirectory $dir -WindowStyle Hidden
        Start-Sleep -Seconds 2
        if (Get-XmrigRunning) {
            return @{ success = $true; message = "XMRig started" }
        } else {
            return @{ success = $false; message = "XMRig process did not start" }
        }
    } catch {
        return @{ success = $false; message = "Error: $_" }
    }
}

function Stop-Xmrig {
    if (-not (Get-XmrigRunning)) {
        return @{ success = $false; message = "XMRig is not running" }
    }
    try {
        Stop-Process -Name "xmrig" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
        return @{ success = $true; message = "XMRig stopped" }
    } catch {
        return @{ success = $false; message = "Error: $_" }
    }
}

function Handle-Command($cmd, $requestId) {
    $result = switch ($cmd) {
        "SET_PERFORMANCE"      { Set-PowerMode "High performance" }
        "SET_BALANCED"         { Set-PowerMode "Balanced" }
        "SET_POWER_EFFICIENCY" { Set-PowerMode "Power saver" }
        "START_XMRIG"         { Start-Xmrig }
        "STOP_XMRIG"          { Stop-Xmrig }
        "GET_STATUS"          { @{ success = $true; message = "Power: $(Get-PowerMode), XMRig: $(if(Get-XmrigRunning){'Running'}else{'Stopped'})" } }
        default               { @{ success = $false; message = "Unknown command: $cmd" } }
    }
    $response = @{
        type      = "command_result"
        requestId = $requestId
        command   = $cmd
        success   = $result.success
        message   = $result.message
    }
    return ($response | ConvertTo-Json -Compress)
}

function Send-WS($ws, $msg) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($msg)
    $seg = [System.ArraySegment[byte]]::new($bytes)
    $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None).Wait()
}

# ============================================================
# MAIN LOOP - Connect, Register, Listen for Commands
# ============================================================
Log "PC-Agent starting. Device: $DeviceName ($DeviceId)"
$httpUrl = ($ServerUrl -replace "wss://", "https://") -replace "ws://", "http://"

while ($true) {
    try {
        $ws = New-Object System.Net.WebSockets.ClientWebSocket
        Log "Connecting to $ServerUrl..."
        $ws.ConnectAsync([Uri]$ServerUrl, [System.Threading.CancellationToken]::None).Wait()
        Log "Connected!"

        # Register
        $reg = @{
            type         = "register"
            deviceId     = $DeviceId
            deviceName   = $DeviceName
            computerName = $env:COMPUTERNAME
            agentVersion = "2.0.0"
        } | ConvertTo-Json -Compress
        Send-WS $ws $reg
        Log "Registered with server."

        $lastHeartbeat = [DateTime]::MinValue
        $lastPing = [DateTime]::MinValue
        $receiveTask = $null
        $buf = $null

        while ($ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {

            # Start a receive if we don't have one pending
            if ($null -eq $receiveTask) {
                $buf = New-Object byte[] 8192
                $seg = [System.ArraySegment[byte]]::new($buf)
                $receiveTask = $ws.ReceiveAsync($seg, [System.Threading.CancellationToken]::None)
            }

            # Check if a message arrived (non-blocking)
            if ($receiveTask.IsCompleted) {
                if ($receiveTask.IsFaulted) {
                    Log "Receive error: $($receiveTask.Exception.InnerException.Message)"
                    break
                }
                if ($receiveTask.Result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                    Log "Server closed connection."
                    break
                }

                $msg = [System.Text.Encoding]::UTF8.GetString($buf, 0, $receiveTask.Result.Count)
                $receiveTask = $null  # Ready for next message

                try {
                    $data = $msg | ConvertFrom-Json

                    if ($data.type -eq "command") {
                        Log "Command received: $($data.command)"
                        $response = Handle-Command $data.command $data.requestId
                        Send-WS $ws $response
                        Log "Command result sent."
                    }
                    elseif ($data.type -eq "policy_update") {
                        Log "Policy update received."
                        $global:currentPolicy = $data.policy
                        $global:lastPolicyTime = $null # Force immediate re-evaluation
                    }
                    elseif ($data.type -eq "override") {
                        $planName = switch -Wildcard ($data.mode) {
                            "*erformance*" { "High performance" }
                            "*alanced*"    { "Balanced" }
                            "*ower*"       { "Power saver" }
                            "*aver*"       { "Power saver" }
                            default        { "Balanced" }
                        }
                        $r = Set-PowerMode $planName
                        Log "Override: $($data.mode) - $($r.message)"
                    }
                } catch {
                    Log "Error processing message: $_"
                }
            }

            # Check policy and heartbeat every 15 seconds
            if (([DateTime]::Now - $lastHeartbeat).TotalSeconds -ge 15) {
                
                # 1. Enforce Policy if enabled
                if ($global:currentPolicy -and $global:currentPolicy.enableAutomaticPolicy) {
                    $now = [DateTime]::Now
                    $currentTime = "$($now.ToString('HH:mm'))"
                    $mode = "Balanced" # Default

                    try {
                        # Using the correct keys from app.js payload
                        $perfStartStr = $global:currentPolicy.performanceStartTime
                        $perfEndStr = $global:currentPolicy.performanceEndTime
                        
                        $perfStart = [DateTime]::Parse($perfStartStr)
                        $perfEnd = [DateTime]::Parse($perfEndStr)
                        $nowTime = [DateTime]::Now

                        # Convert all to today's date for accurate comparison
                        $startToday = Get-Date -Year $nowTime.Year -Month $nowTime.Month -Day $nowTime.Day -Hour $perfStart.Hour -Minute $perfStart.Minute -Second 0
                        $endToday = Get-Date -Year $nowTime.Year -Month $nowTime.Month -Day $nowTime.Day -Hour $perfEnd.Hour -Minute $perfEnd.Minute -Second 0

                        if ($startToday -le $endToday) {
                            # Normal case: Start is before End (e.g. 09:00 to 17:00)
                            if ($nowTime -ge $startToday -and $nowTime -lt $endToday) { $mode = "High performance" }
                            else { $mode = "Power saver" }
                        } else {
                            # Midnight crossing case (e.g. 18:00 to 06:00)
                            if ($nowTime -ge $startToday -or $nowTime -lt $endToday) { $mode = "High performance" }
                            else { $mode = "Power saver" }
                        }
                    } catch {
                        Log "Error parsing policy times. Defaulting to Balanced. Exception: $_"
                    }

                    $currentMode = Get-PowerMode
                    if ($currentMode -notmatch $mode) {
                        Log "Enforcing policy: Switching to $mode"
                        Set-PowerMode $mode | Out-Null
                    }
                }

                # 2. Send Status Heartbeat
                $status = @{
                    type         = "status"
                    deviceId     = $DeviceId
                    powerMode    = (Get-PowerMode)
                    activePolicy = if ($global:currentPolicy -and $global:currentPolicy.enableAutomaticPolicy) { "Active" } else { "Disabled" }
                    xmrigRunning = (Get-XmrigRunning)
                    xmrigHashrate = 0
                } | ConvertTo-Json -Compress
                Send-WS $ws $status
                $lastHeartbeat = [DateTime]::Now
            }



            # Keep Render awake every 10 minutes
            if (([DateTime]::Now - $lastPing).TotalMinutes -ge 10) {
                try {
                    (New-Object System.Net.WebClient).DownloadString("$httpUrl/api/ping") | Out-Null
                } catch {}
                $lastPing = [DateTime]::Now
            }

            # Small sleep to avoid CPU spinning
            Start-Sleep -Milliseconds 500
        }
    } catch {
        Log "Disconnected: $_. Reconnecting in 5s..."
    }

    # Cleanup
    if ($ws) {
        try { $ws.Dispose() } catch {}
    }
    Start-Sleep -Seconds 5
}
