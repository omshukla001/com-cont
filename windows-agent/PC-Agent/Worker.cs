using System.Text.Json;

namespace PC_Agent;

public class Worker : BackgroundService
{
    private readonly ILogger<Worker> _logger;
    private AgentConfig? _config;
    // Hardcoded path to config as requested by the user
    private readonly string _configPath = @"C:\ProgramData\PC-Agent\config.json";

    public Worker(ILogger<Worker> logger)
    {
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("Agent started at: {time}", DateTimeOffset.Now);

        LoadConfig();

        // Phase 1: Just stay alive in the background and log occasionally
        while (!stoppingToken.IsCancellationRequested)
        {
            if (_logger.IsEnabled(LogLevel.Information))
            {
                _logger.LogInformation("Worker running at: {time}. Configured for PC: {PcId}", 
                    DateTimeOffset.Now, _config?.PcId ?? "Unknown");
            }
            
            // Wait for 10 seconds before logging again
            await Task.Delay(10000, stoppingToken);
        }
        
        _logger.LogInformation("Agent is stopping gracefully.");
    }

    private void LoadConfig()
    {
        try
        {
            if (File.Exists(_configPath))
            {
                string json = File.ReadAllText(_configPath);
                var options = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
                _config = JsonSerializer.Deserialize<AgentConfig>(json, options);
                _logger.LogInformation("Successfully loaded config for PC: {PcId}", _config?.PcId);
            }
            else
            {
                _logger.LogWarning("Config file not found at {path}. Using default empty configuration.", _configPath);
                _config = new AgentConfig(); 
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to load config from {path}", _configPath);
            _config = new AgentConfig();
        }
    }
}
