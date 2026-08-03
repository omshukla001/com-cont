using Microsoft.Extensions.Logging.Configuration;
using Microsoft.Extensions.Logging.EventLog;
using System.Text.Json;
using PC_Agent;
using PC_Agent.Services;
using PC_Agent.Workers;

HostApplicationBuilder builder = Host.CreateApplicationBuilder(args);

builder.Services.AddWindowsService(options =>
{
    options.ServiceName = "PC-Agent";
});

LoggerProviderOptions.RegisterProviderOptions<
    EventLogSettings, EventLogLoggerProvider>(builder.Services);

// 1. Load Configuration Immediately
var configPath = @"C:\ProgramData\PC-Agent\config.json";
var config = new AgentConfig();
if (File.Exists(configPath))
{
    try {
        var json = File.ReadAllText(configPath);
        config = JsonSerializer.Deserialize<AgentConfig>(json, new JsonSerializerOptions { PropertyNameCaseInsensitive = true }) ?? new AgentConfig();
    } catch { /* Use defaults if parse fails */ }
}

// 2. Register Singletons
builder.Services.AddSingleton(config);
builder.Services.AddSingleton<PowerManager>();
builder.Services.AddSingleton<PowerPolicyService>();
builder.Services.AddSingleton<XmrigManager>();

// 3. Register Background Workers
builder.Services.AddHostedService<PolicyScheduler>();
builder.Services.AddHostedService<WebSocketClient>();

IHost host = builder.Build();
host.Run();
