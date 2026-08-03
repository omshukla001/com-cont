using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using PC_Agent.Models;

namespace PC_Agent.Services;

public class WebSocketClient : BackgroundService
{
    private readonly AgentConfig _config;
    private readonly PowerPolicyService _policyService;
    private readonly PowerManager _powerManager;
    private readonly ILogger<WebSocketClient> _logger;
    private ClientWebSocket? _ws;

    public WebSocketClient(AgentConfig config, PowerPolicyService policyService, PowerManager powerManager, ILogger<WebSocketClient> logger)
    {
        _config = config;
        _policyService = policyService;
        _powerManager = powerManager;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (string.IsNullOrEmpty(_config.ServerUrl))
        {
            _logger.LogWarning("ServerUrl is empty. Agent will run offline using local policy only.");
            return;
        }

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                _ws = new ClientWebSocket();
                _logger.LogInformation("Connecting to server: {Url}", _config.ServerUrl);
                
                await _ws.ConnectAsync(new Uri(_config.ServerUrl), stoppingToken);
                _logger.LogInformation("Connected to Dashboard Server!");

                // Register with the server
                await SendMessageAsync(new
                {
                    type = "register",
                    deviceId = _config.DeviceId,
                    deviceName = _config.DeviceName,
                    computerName = Environment.MachineName,
                    agentVersion = "1.1.0",
                    token = _config.Token
                }, stoppingToken);

                // Start heartbeat loop
                _ = HeartbeatLoopAsync(stoppingToken);

                // Listen for messages (Policy updates, Manual Overrides)
                var buffer = new byte[8192];
                while (_ws.State == WebSocketState.Open && !stoppingToken.IsCancellationRequested)
                {
                    var result = await _ws.ReceiveAsync(new ArraySegment<byte>(buffer), stoppingToken);
                    if (result.MessageType == WebSocketMessageType.Close) break;

                    string msg = Encoding.UTF8.GetString(buffer, 0, result.Count);
                    HandleMessage(msg);
                }
            }
            catch (Exception ex)
            {
                _logger.LogError("WebSocket disconnected: {Message}. Reconnecting in 5s...", ex.Message);
            }

            await Task.Delay(5000, stoppingToken);
        }
    }

    private async Task HeartbeatLoopAsync(CancellationToken stoppingToken)
    {
        while (_ws?.State == WebSocketState.Open && !stoppingToken.IsCancellationRequested)
        {
            var status = new
            {
                type = "status",
                deviceId = _config.DeviceId,
                powerMode = _powerManager.GetCurrentPowerMode(),
                activePolicy = _policyService.DetermineExpectedPowerMode()
            };
            await SendMessageAsync(status, stoppingToken);
            await Task.Delay(15000, stoppingToken); // 15 seconds heartbeat
        }
    }

    private async Task SendMessageAsync(object data, CancellationToken stoppingToken)
    {
        if (_ws?.State == WebSocketState.Open)
        {
            string json = JsonSerializer.Serialize(data);
            var bytes = Encoding.UTF8.GetBytes(json);
            await _ws.SendAsync(new ArraySegment<byte>(bytes), WebSocketMessageType.Text, true, stoppingToken);
        }
    }

    private void HandleMessage(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            var type = doc.RootElement.GetProperty("type").GetString();

            if (type == "policy_update")
            {
                var policyStr = doc.RootElement.GetProperty("policy").GetRawText();
                var policy = JsonSerializer.Deserialize<PowerPolicy>(policyStr, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
                if (policy != null)
                {
                    _policyService.UpdatePolicy(policy);
                }
            }
            else if (type == "override")
            {
                var mode = doc.RootElement.GetProperty("mode").GetString();
                var duration = doc.RootElement.GetProperty("durationMinutes").GetInt32();
                if (mode != null)
                {
                    _policyService.SetOverride(mode, TimeSpan.FromMinutes(duration));
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogError("Error parsing server message: {Ex}", ex.Message);
        }
    }
}
