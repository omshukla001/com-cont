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
        const res = await fetch('/api/devices');
        const devices = await res.json();
        renderDevices(devices);
    } catch (err) { console.error('Failed to fetch devices', err); }
}

async function loadPolicy() {
    try {
        const res = await fetch('/api/policy');
        const policy = await res.json();
        
        document.getElementById('perf-start').value = policy.performanceStartTime;
        document.getElementById('perf-end').value = policy.performanceEndTime;
        document.getElementById('eff-start').value = policy.efficiencyStartTime;
        document.getElementById('eff-end').value = policy.efficiencyEndTime;
        
        document.getElementById('set-auto').checked = policy.enableAutomaticPolicy;
        document.getElementById('set-startup').checked = policy.applyPolicyAfterStartup;
        document.getElementById('set-reconnect').checked = policy.applyPolicyAfterReconnect;
        document.getElementById('set-reapply').checked = policy.reapplyPolicyEvery5Minutes;
    } catch (err) { console.error('Failed to load policy', err); }
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
    
    await fetch('/api/policy', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(policy)
    });
    alert('Global policy saved and dispatched to all online PCs.');
}

async function applyPolicyNow() {
    await fetch('/api/apply-now', { method: 'POST' });
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
                    <div>Agent Version: <span>${dev.agentVersion || '1.0.0'}</span></div>
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
    
    await fetch('/api/override', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ deviceId: currentOverrideDeviceId, mode, durationMinutes: parseInt(duration) })
    });
    
    closeModal();
    fetchDevices();
}

// Init
loadPolicy();
fetchDevices();
setInterval(fetchDevices, 5000); // Poll for real-time status
