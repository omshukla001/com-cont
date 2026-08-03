# PC-Agent

This is Phase 1 of the Windows PC Remote Control system.

## Build Instructions
Run the following command to build the agent as a standalone executable:
```bash
dotnet publish -c Release -r win-x64 --self-contained true
```
This will produce a standalone executable (e.g., `PC-Agent.exe`) that can run on a Windows PC without requiring the .NET runtime to be installed.

## Windows Service Installation

### 1. Preparation
1. Create a folder on the Windows PC: `C:\Program Files\PC-Agent\`
2. Copy the published `PC-Agent.exe` (and any other generated DLLs in the publish folder) into this directory.
3. Create a folder for the config: `C:\ProgramData\PC-Agent\`
4. Copy `config.example.json` into this folder and rename it to `config.json`.
5. Edit `C:\ProgramData\PC-Agent\config.json` with your actual settings.

### 2. Install the Service
Open an **Administrator PowerShell** or **Command Prompt** and run:
```cmd
sc create "PC-Agent" binPath= "C:\Program Files\PC-Agent\PC-Agent.exe" start= auto
```
*Note: Ensure there is a space after `binPath=` and `start=`.*

### 3. Start the Service
```cmd
sc start "PC-Agent"
```

### 4. Stop the Service
```cmd
sc stop "PC-Agent"
```

### 5. Check Service Status
```cmd
sc query "PC-Agent"
```

### 6. View Logs
The agent logs to the standard Windows Event Viewer.
1. Open Windows Event Viewer (`eventvwr.msc`).
2. Go to **Windows Logs** -> **Application**.
3. Look for logs where the Source is `.NET Runtime` or `PC-Agent` to see startup messages and background logs.

### 7. Uninstall the Service
Ensure the service is stopped first, then run (as Administrator):
```cmd
sc delete "PC-Agent"
```
