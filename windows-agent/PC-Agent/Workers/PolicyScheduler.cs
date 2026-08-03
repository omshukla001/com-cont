using PC_Agent.Services;

namespace PC_Agent.Workers;

public class PolicyScheduler : BackgroundService
{
    private readonly PowerPolicyService _policyService;
    private readonly PowerManager _powerManager;
    private readonly ILogger<PolicyScheduler> _logger;
    private DateTime _lastApplyTime = DateTime.MinValue;

    public PolicyScheduler(PowerPolicyService policyService, PowerManager powerManager, ILogger<PolicyScheduler> logger)
    {
        _policyService = policyService;
        _powerManager = powerManager;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await Task.Delay(5000, stoppingToken); // Small delay on startup

        if (_policyService.GetCurrentPolicy().ApplyPolicyAfterStartup)
        {
            EnforcePolicy();
        }

        // Runs continually every 1 minute
        while (!stoppingToken.IsCancellationRequested)
        {
            await Task.Delay(TimeSpan.FromMinutes(1), stoppingToken);
            EnforcePolicy();
        }
    }

    private void EnforcePolicy()
    {
        var expectedMode = _policyService.DetermineExpectedPowerMode();
        if (string.IsNullOrEmpty(expectedMode)) return;

        var currentMode = _powerManager.GetCurrentPowerMode();
        var policy = _policyService.GetCurrentPolicy();

        bool needsApply = false;

        // Partial match allows "Performance" to match "High performance"
        if (!currentMode.Contains(expectedMode, StringComparison.OrdinalIgnoreCase))
        {
            needsApply = true;
            _logger.LogInformation("Policy mismatch. Expected: {Expected}, Current: {Current}. Will apply.", expectedMode, currentMode);
        }
        else if (policy.ReapplyPolicyEvery5Minutes && (DateTime.Now - _lastApplyTime).TotalMinutes >= 5)
        {
            needsApply = true;
            _logger.LogInformation("Reapplying power policy to ensure compliance (5-min interval).");
        }

        if (needsApply)
        {
            _powerManager.SetPowerMode(expectedMode);
            _lastApplyTime = DateTime.Now;
        }
    }
}
