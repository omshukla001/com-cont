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
    $schemes = powercfg /list
    if ($schemes -notmatch "High performance") {
        Log "Creating 'High performance' power plan..."
        powercfg /duplicatescheme 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
    }
    if ($schemes -notmatch "Power saver") {
        Log "Creating 'Power saver' power plan..."
        powercfg /duplicatescheme a1841308-3541-4fab-bc81-f71556f20b4a
    }
}
Ensure-PowerPlans

function Get-PowerMode {
    try {
        $out = powercfg /getactivescheme
        if ($out -match '\((.+)\)') { return $Matches[1] }
    } catch {}
    return "Unknown"
}

function Set-PowerMode($guid, $label) {
    try {
        powercfg /setactive $guid
        Start-Sleep -Milliseconds 500
        $current = Get-PowerMode
        return @{ success = $true; message = "Set to $current" }
    } catch {
        return @{ success = $false; message = "Failed to set $label : $_" }
    }
}

# Well-known Windows power plan GUIDs
$GUID_HIGH_PERFORMANCE = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
$GUID_BALANCED         = "381b4222-f694-41f0-9685-ff5bb260df2e"
$GUID_POWER_SAVER      = "a1841308-3541-4fab-bc81-f71556f20b4a"

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
        "SET_PERFORMANCE"      { Set-PowerMode $GUID_HIGH_PERFORMANCE "High Performance" }
        "SET_BALANCED"         { Set-PowerMode $GUID_BALANCED "Balanced" }
        "SET_POWER_EFFICIENCY" { Set-PowerMode $GUID_POWER_SAVER "Power Saver" }
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
                    }
                    elseif ($data.type -eq "override") {
                        $modeGuid = switch -Wildcard ($data.mode) {
                            "*erformance*" { $GUID_HIGH_PERFORMANCE }
                            "*alanced*"    { $GUID_BALANCED }
                            "*ower*"       { $GUID_POWER_SAVER }
                            "*aver*"       { $GUID_POWER_SAVER }
                            default        { $GUID_BALANCED }
                        }
                        $r = Set-PowerMode $modeGuid $data.mode
                        Log "Override: $($data.mode) - $($r.message)"
                    }
                } catch {
                    Log "Error processing message: $_"
                }
            }

            # Heartbeat every 15 seconds
            if (([DateTime]::Now - $lastHeartbeat).TotalSeconds -ge 15) {
                $status = @{
                    type         = "status"
                    deviceId     = $DeviceId
                    powerMode    = (Get-PowerMode)
                    activePolicy = ""
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
