const express = require('express');
const http = require('http');
const WebSocket = require('ws');
const path = require('path');

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

// In-memory state for Phase 2.1
const devices = new Map();
let globalPolicy = {
    performanceStartTime: "18:00",
    performanceEndTime: "07:30",
    efficiencyStartTime: "07:30",
    efficiencyEndTime: "18:00",
    enableAutomaticPolicy: true,
    applyPolicyAfterStartup: true,
    applyPolicyAfterReconnect: true,
    reapplyPolicyEvery5Minutes: true
};

app.use(express.json());
app.use(express.static(path.join(__dirname, '../dashboard')));

// --- DASHBOARD API ---
app.get('/api/ping', (req, res) => {
    res.send('pong'); // Keeps the free Render instance awake
});

app.get('/api/devices', (req, res) => {
    res.json(Array.from(devices.values()));
});

app.get('/api/policy', (req, res) => {
    res.json(globalPolicy);
});

app.post('/api/policy', (req, res) => {
    globalPolicy = { ...globalPolicy, ...req.body };
    broadcastPolicy();
    res.json({ success: true });
});

app.post('/api/apply-now', (req, res) => {
    broadcastPolicy();
    res.json({ success: true });
});

app.post('/api/override', (req, res) => {
    const { deviceId, mode, durationMinutes } = req.body;
    const ws = Array.from(wss.clients).find(c => c.deviceId === deviceId);
    if (ws && ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({ type: 'override', mode, durationMinutes }));
        res.json({ success: true });
    } else {
        res.status(404).json({ success: false, error: 'Device offline' });
    }
});

// --- WEBSOCKET FOR AGENTS ---
wss.on('connection', (ws) => {
    ws.on('message', (message) => {
        try {
            const data = JSON.parse(message);
            
            if (data.type === 'register') {
                ws.deviceId = data.deviceId;
                devices.set(data.deviceId, {
                    deviceId: data.deviceId,
                    deviceName: data.deviceName,
                    computerName: data.computerName,
                    status: 'online',
                    powerMode: 'Unknown',
                    activePolicy: 'Unknown',
                    agentVersion: data.agentVersion,
                    connectedSince: new Date().toISOString(),
                    lastSeen: new Date().toISOString()
                });
                console.log(`Registered device: ${data.deviceName}`);
                
                // Immediately send latest policy on reconnect
                ws.send(JSON.stringify({ type: 'policy_update', policy: globalPolicy }));
            }
            else if (data.type === 'status' && ws.deviceId) {
                if (devices.has(ws.deviceId)) {
                    const device = devices.get(ws.deviceId);
                    device.powerMode = data.powerMode;
                    device.activePolicy = data.activePolicy;
                    device.lastSeen = new Date().toISOString();
                }
            }
        } catch (err) {
            console.error('WebSocket message parse error:', err);
        }
    });

    ws.on('close', () => {
        if (ws.deviceId && devices.has(ws.deviceId)) {
            devices.get(ws.deviceId).status = 'offline';
            console.log(`Device offline: ${devices.get(ws.deviceId).deviceName}`);
        }
    });
});

function broadcastPolicy() {
    const msg = JSON.stringify({ type: 'policy_update', policy: globalPolicy });
    wss.clients.forEach(client => {
        if (client.readyState === WebSocket.OPEN && client.deviceId) {
            client.send(msg);
        }
    });
}

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
    console.log(`Phase 2.1 Central Server running on port ${PORT}`);
});
