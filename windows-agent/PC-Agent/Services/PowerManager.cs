using System.Diagnostics;
using System.Text.RegularExpressions;

namespace PC_Agent.Services;

public class PowerManager
{
    private readonly ILogger<PowerManager> _logger;

    public PowerManager(ILogger<PowerManager> logger)
    {
        _logger = logger;
    }

    /// <summary>
    /// Reads the currently active Windows Power Scheme via powercfg.
    /// </summary>
    public string GetCurrentPowerMode()
    {
        var output = RunPowerCfg("/getactivescheme");
        return ExtractSchemeName(output);
    }

    /// <summary>
    /// Dynamically finds the GUID for the requested mode and sets it as active.
    /// </summary>
    public bool SetPowerMode(string modeName)
    {
        var allSchemes = RunPowerCfg("/listschemes");
        var guid = ExtractGuidForName(allSchemes, modeName);
        
        if (string.IsNullOrEmpty(guid))
        {
            _logger.LogWarning("Power mode '{Mode}' not found on this system.", modeName);
            return false;
        }

        RunPowerCfg($"/setactive {guid}");
        
        var current = GetCurrentPowerMode();
        if (current.Contains(modeName, StringComparison.OrdinalIgnoreCase))
        {
            _logger.LogInformation("Successfully applied power mode: {Mode}", modeName);
            return true;
        }
        else
        {
            _logger.LogError("Failed to apply power mode. Attempted: {Mode}, but current is: {Current}", modeName, current);
            return false;
        }
    }

    private string RunPowerCfg(string arguments)
    {
        try
        {
            var process = new Process
            {
                StartInfo = new ProcessStartInfo
                {
                    FileName = "powercfg",
                    Arguments = arguments,
                    RedirectStandardOutput = true,
                    UseShellExecute = false,
                    CreateNoWindow = true
                }
            };
            process.Start();
            string output = process.StandardOutput.ReadToEnd();
            process.WaitForExit();
            return output;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error running powercfg {Args}", arguments);
            return string.Empty;
        }
    }

    private string ExtractSchemeName(string output)
    {
        var match = Regex.Match(output, @"\(([^)]+)\)");
        return match.Success ? match.Groups[1].Value : "Unknown";
    }

    private string ExtractGuidForName(string output, string name)
    {
        var lines = output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
        foreach (var line in lines)
        {
            if (line.Contains(name, StringComparison.OrdinalIgnoreCase))
            {
                var match = Regex.Match(line, @"GUID:\s+([a-fA-F0-9\-]+)");
                if (match.Success) return match.Groups[1].Value;
            }
        }
        return string.Empty;
    }
}
