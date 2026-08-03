const express = require('express');
const http = require('http');
const WebSocket = require('ws');
const path = require('path');
const rateLimit = require('express-rate-limit');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

// --- SECURITY & RATE LIMITING ---
// Global Rate Limit: Protects against general DDoS attacks
const globalLimiter = rateLimit({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 500, // Limit each IP to 500 requests per window
    message: { error: 'Too many requests from this IP, please try again later.' }
});

// Login Rate Limit: Prevents brute-forcing passwords
const loginLimiter = rateLimit({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 10, // Limit each IP to 10 login attempts per window
    message: { error: 'Too many login attempts. Please try again after 15 minutes.' }
});

app.use(express.json());
app.use(globalLimiter);
app.use(express.static(path.join(__dirname, 'public')));

// --- AUTHENTICATION ---
// These will be overridden by Render Environment Variables if set!
const ADMIN_USERNAME = process.env.ADMIN_USERNAME || 'cr';
// This is the SHA256 hash of 'Crmining@2006' so the plaintext password is not exposed in GitHub.
const ADMIN_PASSWORD_HASH = process.env.ADMIN_PASSWORD_HASH || '4f6730ce48be74b1168d1d8f7a4d68e05c49f092dc9a4c50dc468ce803721865';
const JWT_SECRET = process.env.JWT_SECRET || 'fallback-secret-key-12345';

app.post('/api/login', loginLimiter, (req, res) => {
    const { username, password } = req.body;
    
    // Hash the incoming password to check it against our stored hash
    const incomingHash = crypto.createHash('sha256').update(password || '').digest('hex');
    
    if (username === ADMIN_USERNAME && incomingHash === ADMIN_PASSWORD_HASH) {
        // Sign token that lasts for 24 hours
        const token = jwt.sign({ role: 'admin' }, JWT_SECRET, { expiresIn: '24h' });
        res.json({ success: true, token });
    } else {
        res.status(401).json({ success: false, error: 'Invalid credentials' });
    }
});

// Middleware to protect routes
function requireAuth(req, res, next) {
    const authHeader = req.headers['authorization'];
    if (!authHeader) return res.status(401).json({ error: 'Unauthorized' });

    const token = authHeader.split(' ')[1];
    jwt.verify(token, JWT_SECRET, (err, decoded) => {
        if (err) return res.status(401).json({ error: 'Invalid or expired token' });
        next();
    });
}

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

// --- DASHBOARD API ---
app.get('/api/ping', (req, res) => {
    res.send('pong'); // Keeps the free Render instance awake. Does NOT require Auth.
});

// Apply the Auth Middleware to all routes below this line
app.use('/api', requireAuth);

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
    console.log(`Secure Central Server running on port ${PORT}`);
});
