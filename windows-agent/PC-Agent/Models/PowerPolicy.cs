namespace PC_Agent.Models;

public class PowerPolicy
{
    public string PerformanceStartTime { get; set; } = "18:00"; // 6:00 PM
    public string PerformanceEndTime { get; set; } = "07:30";   // 7:30 AM
    public string EfficiencyStartTime { get; set; } = "07:30";  // 7:30 AM
    public string EfficiencyEndTime { get; set; } = "18:00";    // 6:00 PM
    
    public bool EnableAutomaticPolicy { get; set; } = true;
    public bool ApplyPolicyAfterStartup { get; set; } = true;
    public bool ApplyPolicyAfterReconnect { get; set; } = true;
    public bool ReapplyPolicyEvery5Minutes { get; set; } = true;
}

public class ManualOverride
{
    public string TargetMode { get; set; } = string.Empty;
    public DateTime ExpirationTime { get; set; }
}
