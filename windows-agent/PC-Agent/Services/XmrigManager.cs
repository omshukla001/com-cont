using System.Diagnostics;

namespace PC_Agent.Services;

public class XmrigManager
{
    private readonly AgentConfig _config;
    private readonly ILogger<XmrigManager> _logger;
    private Process? _xmrigProcess;

    public XmrigManager(AgentConfig config, ILogger<XmrigManager> logger)
    {
        _config = config;
        _logger = logger;
    }

    public bool IsRunning
    {
        get
        {
            if (_xmrigProcess != null && !_xmrigProcess.HasExited)
                return true;

            // Also check if xmrig is running externally (e.g. started by Task Scheduler)
            var procs = Process.GetProcessesByName("xmrig");
            return procs.Length > 0;
        }
    }

    public (bool success, string message) Start()
    {
        if (string.IsNullOrEmpty(_config.XmrigPath))
            return (false, "XMRig path not configured in config.json");

        if (!File.Exists(_config.XmrigPath))
            return (false, $"XMRig executable not found at: {_config.XmrigPath}");

        if (IsRunning)
            return (false, "XMRig is already running");

        try
        {
            _xmrigProcess = new Process
            {
                StartInfo = new ProcessStartInfo
                {
                    FileName = _config.XmrigPath,
                    WorkingDirectory = Path.GetDirectoryName(_config.XmrigPath) ?? "",
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = false,
                    RedirectStandardError = false
                },
                EnableRaisingEvents = true
            };

            _xmrigProcess.Exited += (_, _) =>
            {
                _logger.LogInformation("XMRig process exited.");
                _xmrigProcess = null;
            };

            _xmrigProcess.Start();
            _logger.LogInformation("XMRig started (PID: {Pid})", _xmrigProcess.Id);
            return (true, $"XMRig started successfully (PID: {_xmrigProcess.Id})");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to start XMRig");
            return (false, $"Failed to start XMRig: {ex.Message}");
        }
    }

    public (bool success, string message) Stop()
    {
        if (!IsRunning)
            return (false, "XMRig is not running");

        try
        {
            // Kill our managed process
            if (_xmrigProcess != null && !_xmrigProcess.HasExited)
            {
                _xmrigProcess.Kill(true);
                _xmrigProcess.WaitForExit(5000);
                _xmrigProcess = null;
            }

            // Also kill any externally running xmrig processes
            foreach (var proc in Process.GetProcessesByName("xmrig"))
            {
                try { proc.Kill(true); } catch { }
            }

            _logger.LogInformation("XMRig stopped.");
            return (true, "XMRig stopped successfully");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to stop XMRig");
            return (false, $"Failed to stop XMRig: {ex.Message}");
        }
    }
}
