using PC_Agent.Models;

namespace PC_Agent.Services;

public class PowerPolicyService
{
    private PowerPolicy _currentPolicy = new PowerPolicy();
    private ManualOverride? _activeOverride = null;
    private readonly ILogger<PowerPolicyService> _logger;

    public PowerPolicyService(ILogger<PowerPolicyService> logger)
    {
        _logger = logger;
    }

    public void UpdatePolicy(PowerPolicy newPolicy)
    {
        _currentPolicy = newPolicy;
        _logger.LogInformation("Global power policy updated in memory.");
    }

    public void SetOverride(string mode, TimeSpan duration)
    {
        _activeOverride = new ManualOverride
        {
            TargetMode = mode,
            ExpirationTime = DateTime.Now.Add(duration)
        };
        _logger.LogInformation("Manual override set to {Mode} until {Time}.", mode, _activeOverride.ExpirationTime);
    }

    /// <summary>
    /// Calculates what the power mode should be right now, based on clock and overrides.
    /// </summary>
    public string DetermineExpectedPowerMode()
    {
        if (_activeOverride != null)
        {
            if (DateTime.Now < _activeOverride.ExpirationTime)
            {
                return _activeOverride.TargetMode;
            }
            else
            {
                _logger.LogInformation("Manual override expired. Returning to global policy.");
                _activeOverride = null;
            }
        }

        if (!_currentPolicy.EnableAutomaticPolicy) return string.Empty;

        var now = DateTime.Now.TimeOfDay;
        var perfStart = TimeSpan.Parse(_currentPolicy.PerformanceStartTime);
        var perfEnd = TimeSpan.Parse(_currentPolicy.PerformanceEndTime);

        bool isPerformanceTime;
        if (perfStart <= perfEnd)
        {
            isPerformanceTime = now >= perfStart && now < perfEnd;
        }
        else // Handles overnight (e.g. 18:00 to 07:30)
        {
            isPerformanceTime = now >= perfStart || now < perfEnd;
        }

        // Note: Windows defaults are typically "High performance", "Balanced", "Power saver"
        return isPerformanceTime ? "Performance" : "Power saver"; 
    }

    public PowerPolicy GetCurrentPolicy() => _currentPolicy;
}
