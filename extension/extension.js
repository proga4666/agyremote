const vscode = require('vscode');
const { spawn, exec } = require('child_process');
const os = require('os');
const path = require('path');

let daemonProcess = null;
let statusBarItem = null;
let currentWebviewView = null;
let serverLogs = [];
let isServerRunning = false;

function getLocalIpAddress() {
    const interfaces = os.networkInterfaces();
    for (const name of Object.keys(interfaces)) {
        for (const iface of interfaces[name]) {
            if (iface.family === 'IPv4' && !iface.internal) {
                return iface.address;
            }
        }
    }
    return '127.0.0.1';
}

function getDaemonScriptPath() {
    // Check if running from workspace or extension dir
    const candidates = [
        path.join(__dirname, '..', 'server', 'host_daemon.py'),
        path.join('c:', 'flut', 'agyremote', 'server', 'host_daemon.py'),
        path.join(__dirname, 'server', 'host_daemon.py')
    ];
    for (const p of candidates) {
        if (require('fs').existsSync(p)) {
            return p;
        }
    }
    return candidates[1];
}

function updateStatusBar(running) {
    if (!statusBarItem) return;
    isServerRunning = running;
    if (running) {
        statusBarItem.text = `$(broadcast) AGY Remote: Active (${getLocalIpAddress()}:7800)`;
        statusBarItem.tooltip = 'Antigravity Remote Companion is RUNNING. Click to manage.';
        statusBarItem.backgroundColor = undefined;
    } else {
        statusBarItem.text = `$(circle-slash) AGY Remote: Stopped`;
        statusBarItem.tooltip = 'Antigravity Remote Companion is STOPPED. Click to start.';
        statusBarItem.backgroundColor = new vscode.ThemeColor('statusBarItem.warningBackground');
    }
    statusBarItem.show();
}

function appendLog(msg) {
    const timestamp = new Date().toLocaleTimeString();
    const logEntry = `[${timestamp}] ${msg}`;
    serverLogs.push(logEntry);
    if (serverLogs.length > 300) serverLogs.shift();
    
    if (currentWebviewView) {
        currentWebviewView.webview.postMessage({
            type: 'log',
            data: logEntry
        });
    }
}

function notifyWebviewState() {
    if (!currentWebviewView) return;
    const config = vscode.workspace.getConfiguration('antigravityRemote');
    currentWebviewView.webview.postMessage({
        type: 'state',
        isRunning: isServerRunning,
        ip: getLocalIpAddress(),
        port: config.get('port', 7800),
        discoveryPort: config.get('discoveryPort', 7801),
        autostart: config.get('autostart', true)
    });
}

function startDaemon() {
    if (daemonProcess) {
        appendLog('Host Daemon is already running.');
        return;
    }

    const scriptPath = getDaemonScriptPath();
    appendLog(`Launching Host Daemon from: ${scriptPath}`);

    const pythonCmd = process.platform === 'win32' ? 'py' : 'python3';
    daemonProcess = spawn(pythonCmd, [scriptPath], {
        cwd: path.dirname(scriptPath),
        env: { ...process.env, PYTHONUNBUFFERED: '1' }
    });

    isServerRunning = true;
    updateStatusBar(true);
    notifyWebviewState();

    daemonProcess.stdout.on('data', (data) => {
        const str = data.toString().trim();
        if (str) appendLog(str);
    });

    daemonProcess.stderr.on('data', (data) => {
        const str = data.toString().trim();
        if (str) appendLog(`[Error] ${str}`);
    });

    daemonProcess.on('close', (code) => {
        appendLog(`Host Daemon stopped (exit code ${code}).`);
        daemonProcess = null;
        isServerRunning = false;
        updateStatusBar(false);
        notifyWebviewState();
    });

    daemonProcess.on('error', (err) => {
        appendLog(`Failed to start daemon process: ${err.message}`);
        daemonProcess = null;
        isServerRunning = false;
        updateStatusBar(false);
        notifyWebviewState();
    });
}

function stopDaemon() {
    if (!daemonProcess) {
        // Kill any existing daemon on port 7800 via taskkill on Windows
        if (process.platform === 'win32') {
            exec('taskkill /F /IM python.exe', () => {
                appendLog('Stopped existing background daemon processes.');
                isServerRunning = false;
                updateStatusBar(false);
                notifyWebviewState();
            });
        }
        return;
    }

    appendLog('Stopping Host Daemon...');
    daemonProcess.kill();
    daemonProcess = null;
    isServerRunning = false;
    updateStatusBar(false);
    notifyWebviewState();
}

function restartDaemon() {
    appendLog('Restarting Host Daemon...');
    stopDaemon();
    setTimeout(() => {
        startDaemon();
    }, 1500);
}

class AntigravityRemoteViewProvider {
    resolveWebviewView(webviewView) {
        currentWebviewView = webviewView;
        webviewView.webview.options = {
            enableScripts: true
        };

        webviewView.webview.html = getWebviewContent();

        webviewView.webview.onDidReceiveMessage(async (message) => {
            switch (message.command) {
                case 'start':
                    startDaemon();
                    break;
                case 'stop':
                    stopDaemon();
                    break;
                case 'restart':
                    restartDaemon();
                    break;
                case 'setAutostart':
                    await vscode.workspace.getConfiguration('antigravityRemote').update('autostart', message.value, vscode.ConfigurationTarget.Global);
                    appendLog(`Autostart setting updated: ${message.value ? 'Enabled' : 'Disabled'}`);
                    notifyWebviewState();
                    break;
                case 'clearLogs':
                    serverLogs = [];
                    currentWebviewView.webview.postMessage({ type: 'clearLogs' });
                    break;
                case 'ready':
                    notifyWebviewState();
                    serverLogs.forEach(l => {
                        currentWebviewView.webview.postMessage({ type: 'log', data: l });
                    });
                    break;
            }
        });
    }
}

function getWebviewContent() {
    return `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Antigravity Remote Companion</title>
    <style>
        :root {
            --bg-color: #121316;
            --surface-color: #1A1C20;
            --surface-container: #22252A;
            --border-color: #2F333B;
            --primary: #8AB4F8;
            --green: #81C995;
            --red: #F28B82;
            --amber: #FDD663;
            --text-primary: #E8EAED;
            --text-secondary: #9AA0A6;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
            background-color: var(--bg-color);
            color: var(--text-primary);
            margin: 0;
            padding: 16px;
            box-sizing: border-box;
            user-select: none;
        }

        .header {
            display: flex;
            align-items: center;
            gap: 10px;
            margin-bottom: 16px;
            padding-bottom: 12px;
            border-bottom: 1px solid var(--border-color);
        }

        .header-title {
            font-size: 14px;
            font-weight: bold;
            letter-spacing: 0.5px;
            color: var(--primary);
        }

        .header-subtitle {
            font-size: 11px;
            color: var(--text-secondary);
        }

        /* Status Card */
        .status-card {
            background-color: var(--surface-color);
            border: 1px solid var(--border-color);
            border-radius: 10px;
            padding: 14px;
            margin-bottom: 14px;
        }

        .status-indicator {
            display: flex;
            align-items: center;
            justify-content: space-between;
            margin-bottom: 12px;
        }

        .pill {
            display: inline-flex;
            align-items: center;
            gap: 6px;
            padding: 4px 10px;
            border-radius: 12px;
            font-size: 11px;
            font-weight: 600;
        }

        .pill-online {
            background-color: rgba(129, 201, 149, 0.15);
            color: var(--green);
            border: 1px solid rgba(129, 201, 149, 0.3);
        }

        .pill-offline {
            background-color: rgba(242, 139, 130, 0.15);
            color: var(--red);
            border: 1px solid rgba(242, 139, 130, 0.3);
        }

        .pulse-dot {
            width: 8px;
            height: 8px;
            border-radius: 50%;
            background-color: currentColor;
            animation: pulse 2s infinite;
        }

        @keyframes pulse {
            0% { transform: scale(0.95); opacity: 0.8; }
            50% { transform: scale(1.3); opacity: 1; }
            100% { transform: scale(0.95); opacity: 0.8; }
        }

        .info-row {
            display: flex;
            justify-content: space-between;
            align-items: center;
            font-size: 12px;
            margin: 6px 0;
        }

        .info-label {
            color: var(--text-secondary);
        }

        .info-val {
            font-family: monospace;
            color: var(--primary);
            background: var(--surface-container);
            padding: 2px 6px;
            border-radius: 4px;
        }

        /* Autostart Checkbox */
        .checkbox-container {
            display: flex;
            align-items: center;
            gap: 8px;
            margin-top: 12px;
            padding-top: 10px;
            border-top: 1px dashed var(--border-color);
            font-size: 12px;
            cursor: pointer;
        }

        .checkbox-container input {
            cursor: pointer;
            accent-color: var(--primary);
        }

        /* Controls */
        .btn-group {
            display: flex;
            gap: 8px;
            margin-bottom: 14px;
        }

        button {
            flex: 1;
            padding: 8px 12px;
            border-radius: 6px;
            font-size: 12px;
            font-weight: bold;
            cursor: pointer;
            border: none;
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 6px;
            transition: all 0.2s ease;
        }

        .btn-primary {
            background-color: var(--primary);
            color: #101214;
        }
        .btn-primary:hover { background-color: #AECBFA; }

        .btn-danger {
            background-color: rgba(242, 139, 130, 0.2);
            color: var(--red);
            border: 1px solid rgba(242, 139, 130, 0.4);
        }
        .btn-danger:hover { background-color: rgba(242, 139, 130, 0.35); }

        .btn-secondary {
            background-color: var(--surface-container);
            color: var(--text-primary);
            border: 1px solid var(--border-color);
        }
        .btn-secondary:hover { background-color: var(--border-color); }

        /* Terminal Logs */
        .logs-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            font-size: 11px;
            font-weight: bold;
            color: var(--text-secondary);
            margin-bottom: 6px;
        }

        .logs-box {
            background-color: #0B0C0E;
            border: 1px solid var(--border-color);
            border-radius: 6px;
            padding: 10px;
            font-family: 'Consolas', 'Courier New', monospace;
            font-size: 11px;
            height: 180px;
            overflow-y: auto;
            color: #C4C7C5;
            line-height: 1.4;
            user-select: text;
        }

        .log-line {
            margin-bottom: 3px;
            word-break: break-all;
        }

        .clear-btn {
            font-size: 10px;
            color: var(--text-secondary);
            cursor: pointer;
            text-decoration: underline;
        }
    </style>
</head>
<body>
    <div class="header">
        <svg width="22" height="22" viewBox="0 0 24 24" fill="var(--primary)">
            <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 17.93c-3.95-.49-7-3.85-7-7.93 0-.62.08-1.21.21-1.79L9 15v1c0 1.1.9 2 2 2v1.93zm6.9-2.54c-.26-.81-1-1.39-1.9-1.39h-1v-3c0-.55-.45-1-1-1H8v-2h2c.55 0 1-.45 1-1V7h2c1.1 0 2-.9 2-2v-.41c2.93 1.19 5 4.06 5 7.41 0 2.08-.8 3.97-2.1 5.39z"/>
        </svg>
        <div>
            <div class="header-title">ANTIGRAVITY REMOTE</div>
            <div class="header-subtitle">Mobile Companion Daemon</div>
        </div>
    </div>

    <!-- Status Card -->
    <div class="status-card">
        <div class="status-indicator">
            <span style="font-size: 12px; font-weight: 600;">Daemon Status:</span>
            <div id="statusPill" class="pill pill-offline">
                <div class="pulse-dot"></div>
                <span id="statusText">STOPPED</span>
            </div>
        </div>

        <div class="info-row">
            <span class="info-label">Host Wi-Fi IP:</span>
            <span id="hostIp" class="info-val">127.0.0.1</span>
        </div>
        <div class="info-row">
            <span class="info-label">WebSocket Port:</span>
            <span id="wsPort" class="info-val">7800</span>
        </div>
        <div class="info-row">
            <span class="info-label">Auto-Discovery UDP:</span>
            <span id="udpPort" class="info-val">7801 (Active)</span>
        </div>

        <!-- Autostart Checkbox -->
        <label class="checkbox-container">
            <input type="checkbox" id="autostartCheckbox" onchange="toggleAutostart(this.checked)">
            <span><strong>Autostart on Antigravity Launch</strong></span>
        </label>
    </div>

    <!-- Action Buttons -->
    <div class="btn-group">
        <button id="btnStart" class="btn-primary" onclick="startServer()">
            ▶ Start Server
        </button>
        <button id="btnStop" class="btn-danger" onclick="stopServer()" style="display:none;">
            ⏹ Stop Server
        </button>
        <button class="btn-secondary" onclick="restartServer()">
            🔄 Restart
        </button>
    </div>

    <!-- Live Logs -->
    <div class="logs-header">
        <span>DAEMON CONSOLE OUTPUT</span>
        <span class="clear-btn" onclick="clearLogs()">Clear</span>
    </div>
    <div id="logsBox" class="logs-box"></div>

    <script>
        const vscode = acquireVsCodeApi();

        window.addEventListener('message', event => {
            const msg = event.data;
            if (msg.type === 'state') {
                updateUIState(msg);
            } else if (msg.type === 'log') {
                addLogLine(msg.data);
            } else if (msg.type === 'clearLogs') {
                document.getElementById('logsBox').innerHTML = '';
            }
        });

        function updateUIState(state) {
            const pill = document.getElementById('statusPill');
            const text = document.getElementById('statusText');
            const btnStart = document.getElementById('btnStart');
            const btnStop = document.getElementById('btnStop');

            if (state.isRunning) {
                pill.className = 'pill pill-online';
                text.innerText = 'ONLINE';
                btnStart.style.display = 'none';
                btnStop.style.display = 'flex';
            } else {
                pill.className = 'pill pill-offline';
                text.innerText = 'STOPPED';
                btnStart.style.display = 'flex';
                btnStop.style.display = 'none';
            }

            document.getElementById('hostIp').innerText = state.ip;
            document.getElementById('wsPort').innerText = state.port;
            document.getElementById('udpPort').innerText = state.discoveryPort + ' (Active)';
            document.getElementById('autostartCheckbox').checked = state.autostart;
        }

        function addLogLine(text) {
            const box = document.getElementById('logsBox');
            const line = document.createElement('div');
            line.className = 'log-line';
            line.innerText = text;
            box.appendChild(line);
            box.scrollTop = box.scrollHeight;
        }

        function startServer() {
            vscode.postMessage({ command: 'start' });
        }

        function stopServer() {
            vscode.postMessage({ command: 'stop' });
        }

        function restartServer() {
            vscode.postMessage({ command: 'restart' });
        }

        function toggleAutostart(val) {
            vscode.postMessage({ command: 'setAutostart', value: val });
        }

        function clearLogs() {
            vscode.postMessage({ command: 'clearLogs' });
        }

        vscode.postMessage({ command: 'ready' });
    </script>
</body>
</html>`;
}

function activate(context) {
    appendLog('Antigravity Remote Companion extension activated.');

    statusBarItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 100);
    statusBarItem.command = 'antigravityRemote.showPanel';
    context.subscriptions.push(statusBarItem);
    updateStatusBar(false);

    const provider = new AntigravityRemoteViewProvider();
    context.subscriptions.push(
        vscode.window.registerWebviewViewProvider('antigravityRemoteView', provider)
    );

    context.subscriptions.push(
        vscode.commands.registerCommand('antigravityRemote.startServer', () => startDaemon()),
        vscode.commands.registerCommand('antigravityRemote.stopServer', () => stopDaemon()),
        vscode.commands.registerCommand('antigravityRemote.restartServer', () => restartDaemon()),
        vscode.commands.registerCommand('antigravityRemote.showPanel', () => {
            vscode.commands.executeCommand('antigravityRemoteView.focus');
        })
    );

    // Check autostart setting
    const config = vscode.workspace.getConfiguration('antigravityRemote');
    if (config.get('autostart', true)) {
        appendLog('Autostart is ENABLED. Launching host daemon...');
        startDaemon();
    }
}

function deactivate() {
    stopDaemon();
}

module.exports = {
    activate,
    deactivate
};
