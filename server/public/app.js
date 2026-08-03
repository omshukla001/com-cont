// Auth State
let authToken = localStorage.getItem('pc_token');

function togglePassword() {
    const input = document.getElementById('login-password');
    const btn = document.getElementById('toggle-password');
    if (input.type === 'password') {
        input.type = 'text';
        btn.textContent = '🙈';
    } else {
        input.type = 'password';
        btn.textContent = '👁';
    }
}

if (authToken) {
    showDashboard();
}

function showDashboard() {
    document.getElementById('login-view').style.display = 'none';
    document.getElementById('app-view').style.display = 'flex';
    loadPolicy();
    fetchDevices();
    if (!window.pollInterval) {
        window.pollInterval = setInterval(fetchDevices, 5000);
    }
}

function showLogin() {
    document.getElementById('login-view').style.display = 'flex';
    document.getElementById('app-view').style.display = 'none';
    if (window.pollInterval) {
        clearInterval(window.pollInterval);
        window.pollInterval = null;
    }
}

async function performLogin() {
    const u = document.getElementById('login-username').value;
    const p = document.getElementById('login-password').value;
    const errEl = document.getElementById('login-error');
    
    try {
        const res = await fetch('/api/login', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ username: u, password: p })
        });
        const data = await res.json();
        
        if (data.success) {
            authToken = data.token;
            localStorage.setItem('pc_token', authToken);
            errEl.style.display = 'none';
            showDashboard();
        } else {
            errEl.innerText = data.error || 'Login failed';
            errEl.style.display = 'block';
        }
    } catch (e) {
        errEl.innerText = 'Network error or rate limited (DDoS protection active).';
        errEl.style.display = 'block';
    }
}

function logout() {
    authToken = null;
    localStorage.removeItem('pc_token');
    showLogin();
}

// Authenticated Fetch Wrapper
async function authFetch(url, options = {}) {
    if (!options.headers) options.headers = {};
    options.headers['Authorization'] = `Bearer ${authToken}`;
    
    const res = await fetch(url, options);
    if (res.status === 401) {
        logout();
        throw new Error('Unauthorized');
    }
    return res;
}

// Navigation
document.getElementById('nav-devices').addEventListener('click', (e) => switchView(e, 'view-devices'));
document.getElementById('nav-policy').addEventListener('click', (e) => switchView(e, 'view-policy'));

function switchView(e, viewId) {
    document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
    document.querySelectorAll('.view').forEach(v => v.classList.remove('active'));
    e.target.classList.add('active');
    document.getElementById(viewId).classList.add('active');
}

// API Calls
async function fetchDevices() {
    try {
        const res = await authFetch('/api/devices');
        const devices = await res.json();
        renderDevices(devices);
    } catch (err) { console.error(err); }
}

async function loadPolicy() {
    try {
        const res = await authFetch('/api/policy');
        const policy = await res.json();
        
        document.getElementById('perf-start').value = policy.performanceStartTime;
        document.getElementById('perf-end').value = policy.performanceEndTime;
        document.getElementById('eff-start').value = policy.efficiencyStartTime;
        document.getElementById('eff-end').value = policy.efficiencyEndTime;
        
        document.getElementById('set-auto').checked = policy.enableAutomaticPolicy;
        document.getElementById('set-startup').checked = policy.applyPolicyAfterStartup;
        document.getElementById('set-reconnect').checked = policy.applyPolicyAfterReconnect;
        document.getElementById('set-reapply').checked = policy.reapplyPolicyEvery5Minutes;
    } catch (err) { console.error(err); }
}

async function savePolicy() {
    const policy = {
        performanceStartTime: document.getElementById('perf-start').value,
        performanceEndTime: document.getElementById('perf-end').value,
        efficiencyStartTime: document.getElementById('eff-start').value,
        efficiencyEndTime: document.getElementById('eff-end').value,
        enableAutomaticPolicy: document.getElementById('set-auto').checked,
        applyPolicyAfterStartup: document.getElementById('set-startup').checked,
        applyPolicyAfterReconnect: document.getElementById('set-reconnect').checked,
        reapplyPolicyEvery5Minutes: document.getElementById('set-reapply').checked
    };
    
    await authFetch('/api/policy', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(policy)
    });
    alert('Global policy saved and dispatched to all online PCs.');
}

async function applyPolicyNow() {
    await authFetch('/api/apply-now', { method: 'POST' });
    alert('Enforcement signal sent to all online PCs.');
}

// Rendering
function renderDevices(devices) {
    const grid = document.getElementById('device-grid');
    grid.innerHTML = '';
    
    if (devices.length === 0) {
        grid.innerHTML = '<p style="color:var(--text-muted)">No devices registered yet.</p>';
        return;
    }

    devices.forEach(dev => {
        const isOnline = dev.status === 'online';
        grid.innerHTML += `
            <div class="card device-card">
                <div class="dev-header">
                    <div class="dev-title">${dev.deviceName}</div>
                    <div class="badge ${isOnline ? 'online' : 'offline'}">${isOnline ? 'ONLINE' : 'OFFLINE'}</div>
                </div>
                <div class="dev-stats">
                    <div>Mode: <span>${dev.powerMode}</span></div>
                    <div>Policy target: <span>${dev.activePolicy}</span></div>
                    <div>Computer: <span>${dev.computerName || 'Unknown'}</span></div>
                </div>
                <button class="btn btn-block" onclick="openOverrideModal('${dev.deviceId}', '${dev.deviceName}')" ${!isOnline ? 'disabled' : ''}>
                    Manual Override
                </button>
            </div>
        `;
    });
}

// Modal Logic
let currentOverrideDeviceId = null;

function openOverrideModal(deviceId, name) {
    currentOverrideDeviceId = deviceId;
    document.getElementById('modal-title').innerText = `Override: ${name}`;
    document.getElementById('override-modal').classList.add('active');
}

function closeModal() {
    document.getElementById('override-modal').classList.remove('active');
    currentOverrideDeviceId = null;
}

async function submitOverride() {
    if (!currentOverrideDeviceId) return;
    
    const mode = document.getElementById('override-mode').value;
    const duration = document.getElementById('override-duration').value;
    
    await authFetch('/api/override', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ deviceId: currentOverrideDeviceId, mode, durationMinutes: parseInt(duration) })
    });
    
    closeModal();
    fetchDevices();
}
