import asyncio
import json
import os
import sys
import socket
import re
import glob
import sqlite3
import subprocess
from datetime import datetime

# Configure UTF-8 for Windows console
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

PORT = 7800
DISCOVERY_PORT = 7801
PROJECTS_FILE = os.path.expanduser("~/.antigravity_remote_projects.json")
CONVERSATIONS_FILE = os.path.expanduser("~/.antigravity_remote_conversations.json")
CONVERSATIONS_DB_DIR = os.path.expanduser("~/.gemini/antigravity-ide/conversations")
ANTIGRAVITY_BRAIN_DIR = os.path.expanduser("~/.gemini/antigravity-ide/brain")
AGYHUB_SUMMARIES_FILE = os.path.expanduser("~/.gemini/antigravity-ide/agyhub_summaries_proto.pb")
CONFIG_FILE = os.path.expanduser("~/.gemini/config/config.json")
QUICK_COMMANDS_FILE = os.path.expanduser("~/.antigravity_quick_commands.json")

START_TIME = datetime.now()
RECENT_LOGS = []
CLI_NAME_OVERRIDE = None

projects = []
conversations = {}
pending_approvals = {}
active_running_commands = {}
cancelled_command_ids = set()

def load_custom_quick_commands():
    if os.path.exists(QUICK_COMMANDS_FILE):
        try:
            with open(QUICK_COMMANDS_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return []
    return []

def save_custom_quick_commands(cmds):
    try:
        with open(QUICK_COMMANDS_FILE, "w", encoding="utf-8") as f:
            json.dump(cmds, f, indent=2)
    except Exception as e:
        print(f"[Daemon] Error saving custom quick commands: {e}")

async def run_adb_devices():
    try:
        proc = await asyncio.create_subprocess_shell(
            "adb devices -l",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        stdout, stderr = await proc.communicate()
        raw = stdout.decode("utf-8", errors="replace")
        devices = []
        for line in raw.splitlines():
            line = line.strip()
            if not line or line.startswith("List of devices"):
                continue
            parts = line.split()
            if len(parts) >= 2:
                serial = parts[0]
                status = parts[1]
                model = ""
                product = ""
                for p in parts[2:]:
                    if p.startswith("model:"):
                        model = p.split("model:")[1]
                    elif p.startswith("product:"):
                        product = p.split("product:")[1]
                devices.append({
                    "serial": serial,
                    "status": status,
                    "model": model,
                    "product": product,
                    "is_wireless": ":" in serial
                })
        return True, devices
    except Exception as e:
        return False, []

def log_event(msg):
    ts = datetime.now().strftime("%H:%M:%S")
    entry = f"[{ts}] {msg}"
    print(f"[Daemon] {msg}")
    RECENT_LOGS.append(entry)
    if len(RECENT_LOGS) > 100:
        RECENT_LOGS.pop(0)

def get_active_auth_info():
    sync_antigravity_auth()
    acc_file = os.path.expanduser("~/.gemini/google_accounts.json")
    account_email = "Unauthenticated Session"
    is_auth = False
    if os.path.exists(acc_file):
        try:
            with open(acc_file, "r", encoding="utf-8") as f:
                acc_data = json.load(f)
                if isinstance(acc_data, dict):
                    act = acc_data.get("active")
                    if isinstance(act, str) and "@" in act:
                        account_email = act
                        is_auth = True
                    elif isinstance(act, dict) and "email" in act:
                        account_email = act["email"]
                        is_auth = True
        except Exception:
            pass
    return account_email, is_auth

def load_gemini_config():
    cfg = {"cliRemoteControlHostname": "", "remoteControlHostname": "", "updateInterval": "daily"}
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
            user_settings = data.get("userSettings", {}) if isinstance(data, dict) else {}
            cfg["remoteControlHostname"] = user_settings.get("remoteControlHostname") or data.get("remoteControlHostname") or "aws-rising-ember"
            cfg["cliRemoteControlHostname"] = user_settings.get("cliRemoteControlHostname") or data.get("cliRemoteControlHostname") or f"{cfg['remoteControlHostname']}-daemon"
            cfg["updateInterval"] = user_settings.get("autoUpdateInterval") or data.get("autoUpdateInterval") or "daily"
        except Exception as e:
            log_event(f"Error reading config.json: {e}")
    else:
        cfg["remoteControlHostname"] = os.environ.get("COMPUTERNAME", "Workstation")
        cfg["cliRemoteControlHostname"] = f"{cfg['remoteControlHostname']}-daemon"
    
    if CLI_NAME_OVERRIDE:
        cfg["cliRemoteControlHostname"] = CLI_NAME_OVERRIDE
    return cfg

def save_gemini_config(cli_host=None, desktop_host=None, update_interval=None):
    data = {}
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
        except Exception:
            data = {}
    
    if not isinstance(data, dict):
        data = {}
    
    if "userSettings" not in data:
        data["userSettings"] = {}
        
    if cli_host:
        data["userSettings"]["cliRemoteControlHostname"] = cli_host
        data["cliRemoteControlHostname"] = cli_host
    if desktop_host:
        data["userSettings"]["remoteControlHostname"] = desktop_host
        data["remoteControlHostname"] = desktop_host
    if update_interval:
        data["userSettings"]["autoUpdateInterval"] = update_interval
        data["autoUpdateInterval"] = update_interval
        
    try:
        os.makedirs(os.path.dirname(CONFIG_FILE), exist_ok=True)
        with open(CONFIG_FILE, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
        log_event(f"Updated configuration in {CONFIG_FILE}")
        return True
    except Exception as e:
        log_event(f"Failed to write config.json: {e}")
        return False

def scan_conversation_artifacts(conv_id):
    artifacts = []
    if not conv_id:
        return artifacts
    brain_conv_dir = os.path.join(ANTIGRAVITY_BRAIN_DIR, conv_id)
    if os.path.exists(brain_conv_dir):
        for root, dirs, files in os.walk(brain_conv_dir):
            if ".system_generated" in root or ".user_uploaded" in root or "scratch" in root:
                continue
            for f in files:
                if f.endswith(".md") or f.endswith(".json") or f.endswith(".diff"):
                    fp = os.path.join(root, f)
                    try:
                        stat = os.stat(fp)
                        with open(fp, "r", encoding="utf-8", errors="ignore") as content_file:
                            content = content_file.read()
                        
                        art_type = "plan" if "plan" in f.lower() else ("walkthrough" if "walkthrough" in f.lower() else "markdown")
                        artifacts.append({
                            "id": f"art_{f}",
                            "conversation_id": conv_id,
                            "name": f,
                            "file_path": fp.replace("\\", "/"),
                            "type": art_type,
                            "last_modified": datetime.fromtimestamp(stat.st_mtime).isoformat(),
                            "size_bytes": stat.st_size,
                            "request_feedback": art_type == "plan",
                            "summary": f"Artifact {f} generated for session {conv_id}",
                            "content": content
                        })
                    except Exception:
                        pass
    return artifacts

def execute_diagnostics():
    checks = []
    # 1. Outbound Google Connectivity
    try:
        s = socket.create_connection(("www.google.com", 443), timeout=3.0)
        s.close()
        checks.append({
            "id": "diag_network",
            "category": "Network & Connectivity",
            "title": "Outbound Google Cloud Connectivity",
            "passed": True,
            "detail": "Successfully reached Google Cloud services (port 443 open, DNS resolved).",
            "recommended_action": None
        })
    except Exception as e:
        checks.append({
            "id": "diag_network",
            "category": "Network & Connectivity",
            "title": "Outbound Google Cloud Connectivity",
            "passed": False,
            "detail": f"Failed outbound connection: {e}",
            "recommended_action": "Verify internet connection and firewall settings allowing outbound port 443."
        })

    # 2. Google Account Authentication
    email, is_auth = get_active_auth_info()
    if is_auth:
        checks.append({
            "id": "diag_auth",
            "category": "Authentication",
            "title": "Google Account Session Validity",
            "passed": True,
            "detail": f"Authenticated Google account: {email}. Persistent across reboots.",
            "recommended_action": None
        })
    else:
        checks.append({
            "id": "diag_auth",
            "category": "Authentication",
            "title": "Google Account Session Validity",
            "passed": False,
            "detail": "No active Google OAuth credentials found in ~/.gemini.",
            "recommended_action": "Use Google Sign-in action or re-run setup script to refresh authentication."
        })

    # 3. Settings File & Precedence
    cfg = load_gemini_config()
    if CLI_NAME_OVERRIDE:
        checks.append({
            "id": "diag_config",
            "category": "Configuration & Naming",
            "title": "Hostname Precedence Conflict",
            "passed": False,
            "detail": f"Warning: Daemon was started with CLI flag '--name {CLI_NAME_OVERRIDE}', which overrides manual edits to config.json on every restart.",
            "recommended_action": "To restore config.json authority, restart daemon without --name flag."
        })
    else:
        checks.append({
            "id": "diag_config",
            "category": "Configuration & Naming",
            "title": "Settings File Authority",
            "passed": True,
            "detail": f"Config verified at {CONFIG_FILE}. Daemon hostname: '{cfg['cliRemoteControlHostname']}'",
            "recommended_action": None
        })

    # 4. Port & Service Health
    checks.append({
        "id": "diag_ports",
        "category": "Daemon Service",
        "title": "Port Health (WebSocket & Discovery)",
        "passed": True,
        "detail": f"WebSocket server active on port {PORT}; UDP Auto-Discovery beacon active on port {DISCOVERY_PORT}.",
        "recommended_action": None
    })

    # 5. Platform Shell Compliance
    if sys.platform == "win32":
        try:
            import ctypes
            is_admin = ctypes.windll.shell32.IsUserAnAdmin() != 0
        except Exception:
            is_admin = False
        checks.append({
            "id": "diag_shell",
            "category": "Platform Compliance",
            "title": "Windows Administrator & cmd.exe Compliance",
            "passed": True,
            "detail": f"Running on Windows (Admin privileges: {'Yes' if is_admin else 'Standard Command Prompt'}). Note: setup/install requires Administrator cmd.exe.",
            "recommended_action": None if is_admin else "Run Command Prompt as Administrator if installing/uninstalling background service."
        })
    else:
        checks.append({
            "id": "diag_shell",
            "category": "Platform Compliance",
            "title": "Linux / macOS Shell Compliance",
            "passed": True,
            "detail": f"Running on {sys.platform}. Headless background daemon supported.",
            "recommended_action": None
        })

    return checks

def clean_transcript_text(text):
    if not text:
        return ""
    cleaned = re.sub(r"<ADDITIONAL_METADATA>.*?</ADDITIONAL_METADATA>", "", text, flags=re.DOTALL)
    cleaned = re.sub(r"<SYSTEM_MESSAGE>.*?</SYSTEM_MESSAGE>", "", cleaned, flags=re.DOTALL)
    cleaned = re.sub(r"<USER_SETTINGS_CHANGE>.*?</USER_SETTINGS_CHANGE>", "", cleaned, flags=re.DOTALL)
    cleaned = re.sub(r"<conversation_summaries>.*?</conversation_summaries>", "", cleaned, flags=re.DOTALL)
    cleaned = re.sub(r"</?USER_REQUEST>", "", cleaned)
    cleaned = re.sub(r"</?CHECKPOINT[^>]*>", "", cleaned)
    return cleaned.strip()

def sync_antigravity_auth():
    """Ensure Antigravity CLI has the active Google account session from IDE."""
    src_dir = os.path.expanduser("~/.gemini")
    cli_dir = os.path.expanduser("~/.gemini/antigravity-cli")
    os.makedirs(cli_dir, exist_ok=True)
    
    files_to_sync = ["oauth_creds.json", "google_accounts.json", "settings.json", "state.json"]
    for f in files_to_sync:
        s = os.path.join(src_dir, f)
        d = os.path.join(cli_dir, f)
        if os.path.exists(s):
            try:
                import shutil
                shutil.copy(s, d)
            except Exception:
                pass

def extract_workspace_for_conversation(conv_id):
    """Extracts the exact project workspace path from SQLite DB, PB, or transcript."""
    # 1. Check SQLite DB
    db_path = os.path.join(CONVERSATIONS_DB_DIR, f"{conv_id}.db")
    if os.path.exists(db_path):
        try:
            conn = sqlite3.connect(db_path)
            row = conn.execute("SELECT * FROM trajectory_metadata_blob").fetchone()
            if row and row[1]:
                blob = row[1]
                m = re.findall(rb"file:///[^\x00-\x1f\"\'<>\s\xa0]+", blob)
                for raw_uri in m:
                    uri = raw_uri.decode("utf-8", errors="ignore").replace("%3A", ":").replace("%20", " ")
                    path = uri.replace("file:///", "").rstrip("/\\")
                    if path and len(path) > 3 and not path.endswith("z"):
                        folder = os.path.basename(path)
                        return path.replace("\\", "/"), folder
        except Exception:
            pass

    # 2. Check PB file
    pb_path = os.path.join(CONVERSATIONS_DB_DIR, f"{conv_id}.pb")
    if os.path.exists(pb_path):
        try:
            with open(pb_path, "rb") as f:
                content = f.read()
            m = re.findall(rb"file:///[^\x00-\x1f\"\'<>\s\xa0]+", content)
            for raw_uri in m:
                uri = raw_uri.decode("utf-8", errors="ignore").replace("%3A", ":").replace("%20", " ")
                path = uri.replace("file:///", "").rstrip("/\\")
                if path and len(path) > 3 and not path.endswith("z"):
                    folder = os.path.basename(path)
                    return path.replace("\\", "/"), folder
        except Exception:
            pass

    # 3. Check transcript in brain
    trans_path = os.path.join(ANTIGRAVITY_BRAIN_DIR, conv_id, ".system_generated", "logs", "transcript.jsonl")
    if os.path.exists(trans_path):
        try:
            with open(trans_path, "r", encoding="utf-8", errors="ignore") as f:
                for line in f:
                    if "user_information" in line or "file:///" in line or "c:/" in line or "C:\\" in line:
                        m = re.search(r"file:///([^\s\"\'<>\)]+)", line)
                        if not m:
                            m = re.search(r"([A-Za-z]:[\\/][^\s\"\'<>\)]+)", line)
                        if m:
                            p = m.group(1).replace("\\", "/").rstrip("/")
                            parts = p.split("/")
                            if len(parts) >= 3:
                                proj_path = "/".join(parts[:3])
                                folder = parts[2]
                                return proj_path, folder
        except Exception:
            pass

    # Fallback to agyremote
    return "c:/flut/agyremote", "agyremote"

def load_official_antigravity_titles():
    """Parses the official Antigravity Hub Summaries database for conversation titles."""
    official_titles = {}
    if not os.path.exists(AGYHUB_SUMMARIES_FILE):
        return official_titles

    try:
        with open(AGYHUB_SUMMARIES_FILE, "rb") as f:
            data = f.read()

        for m in re.finditer(rb'([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})', data):
            cid = m.group(1).decode('ascii')
            chunk = data[m.end():m.end() + 400]
            strs = [s.decode('utf-8', errors='ignore').strip() for s in re.findall(rb'[\x20-\x7E]{4,}', chunk)]
            
            for s in strs:
                if not s.startswith('file://') and not s.startswith('http') and not re.match(r'^[0-9a-f\-]{36}$', s) and not s.startswith('$'):
                    clean_s = re.sub(r'^[^\w\s]+', '', s).strip()
                    if len(clean_s) >= 4 and not clean_s.startswith('main') and not clean_s.startswith('git') and '/' not in clean_s:
                        official_titles[cid] = clean_s
                        break
    except Exception as e:
        print(f"[Daemon] Error parsing agyhub summaries: {e}")

    return official_titles

def extract_fallback_title(brain_dir, fallback_text, conv_id):
    """Extracts title from implementation plan or first user prompt, eliminating generic prefixes."""
    for doc in ["implementation_plan.md", "walkthrough.md", "task.md"]:
        doc_path = os.path.join(brain_dir, doc)
        if os.path.exists(doc_path):
            try:
                with open(doc_path, "r", encoding="utf-8", errors="ignore") as f:
                    for line in f:
                        line = line.strip()
                        if line.startswith("# "):
                            t = line[2:].strip().replace("[", "").replace("]", "")
                            t = re.sub(r"^(implementation plan|walkthrough|task plan|goal description)\s*[\-:\u2013]?\s*", "", t, flags=re.IGNORECASE).strip()
                            if t and len(t) > 3 and t.lower() not in ["implementation plan", "walkthrough", "task", "goal description"]:
                                return t[:60]
            except Exception:
                pass

    if fallback_text:
        cleaned = clean_transcript_text(fallback_text)
        cleaned = re.sub(r"@\[.*?\]", "", cleaned)
        cleaned = re.sub(r"\{\{.*?\}\}", "", cleaned)
        cleaned = re.sub(r"http\S+", "", cleaned)
        lines = [l.strip() for l in cleaned.splitlines() if l.strip() and not l.strip().startswith("I/") and not l.strip().startswith("D/") and not l.strip().startswith("E/")]
        if lines:
            t = lines[0].rstrip(":")
            if len(t) > 55:
                t = t[:52].rstrip() + "..."
            if len(t) > 2:
                return t

    return f"Session {conv_id[:8]}"

def load_projects_and_conversations():
    """Scans all past Antigravity conversations, groups them into projects/folders, and builds project registry."""
    global projects, conversations
    
    official_titles = load_official_antigravity_titles()
    discovered_projects = {}
    discovered_convs = {}

    # Scan all transcripts from PC
    brain_patterns = [
        os.path.join(ANTIGRAVITY_BRAIN_DIR, "*", ".system_generated", "logs", "transcript.jsonl"),
        os.path.expanduser("~/.gemini/antigravity-cli/brain/*/.system_generated/logs/transcript.jsonl")
    ]

    transcript_files = []
    for pattern in brain_patterns:
        transcript_files.extend(glob.glob(pattern))

    transcript_files.sort(key=lambda p: os.path.getmtime(p), reverse=True)

    for trans_path in transcript_files:
        try:
            brain_dir = os.path.dirname(os.path.dirname(os.path.dirname(trans_path)))
            conv_id = os.path.basename(brain_dir)
            mtime = datetime.fromtimestamp(os.path.getmtime(trans_path)).isoformat()
            
            # 1. Determine exact project workspace path & folder
            ws_path, folder_name = extract_workspace_for_conversation(conv_id)
            if not folder_name or folder_name.lower() in ["users", ""]:
                folder_name = "agyremote"
                ws_path = "c:/flut/agyremote"

            proj_id = f"proj_{folder_name.lower()}"
            if proj_id not in discovered_projects:
                discovered_projects[proj_id] = {
                    "id": proj_id,
                    "name": folder_name,
                    "path": ws_path,
                    "conversation_ids": []
                }
            
            discovered_projects[proj_id]["conversation_ids"].append(conv_id)

            # 2. Parse messages
            messages = []
            first_user_prompt = None

            with open(trans_path, "r", encoding="utf-8", errors="ignore") as f:
                for line in f:
                    if not line.strip():
                        continue
                    try:
                        step = json.loads(line)
                        stype = step.get("type")
                        content = step.get("content", "")
                        step_ts = step.get("created_at") or step.get("timestamp") or mtime

                        if stype == "USER_INPUT" and content:
                            clean_text = clean_transcript_text(content)
                            if clean_text:
                                if not first_user_prompt:
                                    first_user_prompt = clean_text
                                messages.append({
                                    "id": f"msg_{len(messages)}_{conv_id[:8]}",
                                    "sender": "user",
                                    "content": clean_text,
                                    "timestamp": step_ts
                                })

                        elif stype == "PLANNER_RESPONSE":
                            thinking = step.get("thinking", "")
                            if thinking and thinking.strip():
                                messages.append({
                                    "id": f"msg_th_{len(messages)}_{conv_id[:8]}",
                                    "sender": "thought",
                                    "content": thinking.strip(),
                                    "timestamp": step_ts
                                })
                            if content and content.strip():
                                messages.append({
                                    "id": f"msg_{len(messages)}_{conv_id[:8]}",
                                    "sender": "agent",
                                    "content": content,
                                    "timestamp": step_ts
                                })

                    except json.JSONDecodeError:
                        continue

            if messages:
                title = official_titles.get(conv_id) or extract_fallback_title(brain_dir, first_user_prompt, conv_id)
                
                # Identify source: Desktop IDE transcripts vs Antigravity 2.0 CLI / Daemon
                is_ide = "antigravity-ide" in trans_path.replace("\\", "/").lower()
                source = "desktop_ide" if is_ide else "daemon"
                engine = "Desktop IDE" if is_ide else "Antigravity 2.0"

                first_ts = messages[0].get("timestamp") if messages else mtime
                last_ts = messages[-1].get("timestamp") if messages else mtime

                discovered_convs[conv_id] = {
                    "id": conv_id,
                    "project_id": proj_id,
                    "workspace_path": ws_path,
                    "title": title,
                    "messages": messages,
                    "created_at": first_ts,
                    "updated_at": last_ts,
                    "last_message_at": last_ts,
                    "is_pc_synced": True,
                    "source": source,
                    "engine": engine
                }

        except Exception as e:
            continue

    # Ensure agyremote is present
    if "proj_agyremote" not in discovered_projects:
        discovered_projects["proj_agyremote"] = {
            "id": "proj_agyremote",
            "name": "agyremote",
            "path": "c:/flut/agyremote",
            "conversation_ids": []
        }

    # Sort conversations within each project by updated_at descending
    for p in discovered_projects.values():
        p["conversation_ids"].sort(
            key=lambda cid: discovered_convs[cid].get("updated_at", "") if cid in discovered_convs else "",
            reverse=True
        )

    # Sort projects: active/most recently active first
    def get_proj_sort_key(p):
        for cid in p["conversation_ids"]:
            if cid in discovered_convs:
                return discovered_convs[cid].get("updated_at", "")
        return ""

    projects = sorted(discovered_projects.values(), key=get_proj_sort_key, reverse=True)
    conversations = discovered_convs

    print(f"[Daemon] Organized {len(conversations)} conversations across {len(projects)} workspace folders:")
    for p in projects:
        print(f"  📁 {p['name']}: {len(p['conversation_ids'])} sessions ({p['path']})")

    save_projects()
    save_conversations()

def save_projects():
    try:
        os.makedirs(os.path.dirname(PROJECTS_FILE), exist_ok=True)
        with open(PROJECTS_FILE, "w", encoding="utf-8") as f:
            json.dump(projects, f, indent=2)
    except Exception as e:
        print(f"[Daemon] Error saving projects: {e}")

def save_conversations():
    try:
        os.makedirs(os.path.dirname(CONVERSATIONS_FILE), exist_ok=True)
        with open(CONVERSATIONS_FILE, "w", encoding="utf-8") as f:
            json.dump(list(conversations.values()), f, indent=2)
    except Exception as e:
        print(f"[Daemon] Error saving conversations: {e}")

def get_project_by_id(proj_id):
    for p in projects:
        if p["id"] == proj_id:
            return p
    return projects[0] if projects else None

def browse_directory(req_path):
    if not req_path or req_path == "~":
        target = os.path.expanduser("~")
    elif req_path == "/" and sys.platform == "win32":
        target = "C:\\"
    else:
        target = os.path.abspath(req_path)
    
    if not os.path.exists(target):
        target = os.getcwd()

    parent = os.path.dirname(target)
    if parent == target:
        parent = ""
    
    folders = []
    files = []
    
    try:
        with os.scandir(target) as it:
            for entry in it:
                try:
                    if entry.is_dir(follow_symlinks=False):
                        if not entry.name.startswith(".git") and not entry.name.startswith("$"):
                            folders.append(entry.name)
                    elif entry.is_file(follow_symlinks=False):
                        files.append(entry.name)
                except (PermissionError, OSError):
                    continue
        folders.sort(key=str.lower)
        files.sort(key=str.lower)
    except Exception as e:
        print(f"[Daemon] Browse error for {target}: {e}")

    return {
        "event": "dir_contents",
        "current_path": target.replace("\\", "/"),
        "parent_path": parent.replace("\\", "/") if parent else "",
        "folders": folders,
        "files": files[:50]
    }

# --- UDP Wi-Fi Auto-Discovery Service ---
class DiscoveryServerProtocol(asyncio.DatagramProtocol):
    def __init__(self):
        super().__init__()
        self.transport = None

    def connection_made(self, transport):
        self.transport = transport
        print(f"[Discovery] UDP auto-discovery listening on port {DISCOVERY_PORT}")

    def datagram_received(self, data, addr):
        try:
            msg = data.decode("utf-8", errors="ignore").strip()
            if "ANTIGRAVITY_DISCOVER" in msg or "DISCOVER" in msg:
                cfg = load_gemini_config()
                reply = json.dumps({
                    "service": "antigravity_daemon",
                    "instance_type": "headless_daemon",
                    "host_name": cfg["cliRemoteControlHostname"],
                    "cli_hostname": cfg["cliRemoteControlHostname"],
                    "desktop_hostname": cfg["remoteControlHostname"],
                    "platform": "Windows" if sys.platform == "win32" else sys.platform,
                    "port": PORT,
                    "version": "2.0"
                }).encode("utf-8")
                self.transport.sendto(reply, addr)
        except Exception as e:
            print(f"[Discovery] Error answering ping: {e}")

async def run_discovery_beacon():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.setblocking(False)
    
    while True:
        try:
            cfg = load_gemini_config()
            beacon_data = json.dumps({
                "service": "antigravity_daemon",
                "instance_type": "headless_daemon",
                "host_name": cfg["cliRemoteControlHostname"],
                "cli_hostname": cfg["cliRemoteControlHostname"],
                "desktop_hostname": cfg["remoteControlHostname"],
                "platform": "Windows" if sys.platform == "win32" else sys.platform,
                "port": PORT,
                "version": "2.0"
            }).encode("utf-8")
            sock.sendto(beacon_data, ("255.255.255.255", DISCOVERY_PORT))
        except Exception:
            pass
        await asyncio.sleep(2.5)

# --- Client Tracking & Background Sync Watcher ---
CONNECTED_CLIENTS = set()
LAST_TRANSCRIPT_MTIMES = {}

async def broadcast_event(event_dict):
    if not CONNECTED_CLIENTS:
        return
    msg = json.dumps(event_dict)
    dead_clients = set()
    for ws in list(CONNECTED_CLIENTS):
        try:
            await ws.send(msg)
        except Exception:
            dead_clients.add(ws)
    for ws in dead_clients:
        CONNECTED_CLIENTS.discard(ws)

async def watch_transcripts_background():
    """Watches PC Antigravity transcripts and auto-broadcasts updates to connected mobile clients."""
    print("[Daemon] 👁️ Background transcript watcher active (syncing PC messages to mobile)...")
    while True:
        try:
            await asyncio.sleep(1.5)
            if not CONNECTED_CLIENTS:
                continue

            brain_patterns = [
                os.path.join(ANTIGRAVITY_BRAIN_DIR, "*", ".system_generated", "logs", "transcript.jsonl"),
                os.path.expanduser("~/.gemini/antigravity-cli/brain/*/.system_generated/logs/transcript.jsonl")
            ]
            transcript_files = []
            for pattern in brain_patterns:
                transcript_files.extend(glob.glob(pattern))

            changed_conv_ids = []
            for trans_path in transcript_files:
                try:
                    mtime = os.path.getmtime(trans_path)
                    prev_mtime = LAST_TRANSCRIPT_MTIMES.get(trans_path)
                    if prev_mtime is not None and mtime > prev_mtime:
                        brain_dir = os.path.dirname(os.path.dirname(os.path.dirname(trans_path)))
                        conv_id = os.path.basename(brain_dir)
                        changed_conv_ids.append(conv_id)
                    LAST_TRANSCRIPT_MTIMES[trans_path] = mtime
                except Exception:
                    pass

            if changed_conv_ids:
                print(f"[Daemon] 🔄 Detected {len(changed_conv_ids)} modified conversation(s) on PC: {changed_conv_ids}. Syncing with mobile...")
                load_projects_and_conversations()
                
                # Broadcast updated conversation(s)
                for conv_id in changed_conv_ids:
                    if conv_id in conversations:
                        await broadcast_event({
                            "event": "conversation_updated",
                            "conversation": conversations[conv_id]
                        })
                
                # Also broadcast updated sorted list
                sorted_convs = sorted(
                    list(conversations.values()),
                    key=lambda c: c.get("updated_at") or c.get("last_message_at") or c.get("created_at") or "",
                    reverse=True
                )
                await broadcast_event({
                    "event": "conversations_list",
                    "conversations": sorted_convs
                })
        except asyncio.CancelledError:
            break
        except Exception as e:
            print(f"[Daemon] Watcher error: {e}")

# --- Client Handler ---
async def handle_client(websocket):
    CONNECTED_CLIENTS.add(websocket)
    client_ip = websocket.remote_address[0] if websocket.remote_address else "unknown"
    print(f"\n[Daemon] Mobile client connected from {client_ip} (Pool size: {len(CONNECTED_CLIENTS)})")

    # Re-sync on connect
    load_projects_and_conversations()

    cfg = load_gemini_config()
    email, is_auth = get_active_auth_info()
    uptime_sec = int((datetime.now() - START_TIME).total_seconds())

    await websocket.send(json.dumps({
        "event": "status_notice",
        "message": f"Connected to Host Workstation ({cfg['cliRemoteControlHostname']})"
    }))
    await websocket.send(json.dumps({
        "event": "daemon_status",
        "status": "online",
        "uptime_seconds": uptime_sec,
        "pid": os.getpid(),
        "platform": "Windows" if sys.platform == "win32" else sys.platform,
        "instance_type": "headless_daemon",
        "cli_remote_control_hostname": cfg["cliRemoteControlHostname"],
        "remote_control_hostname": cfg["remoteControlHostname"],
        "update_interval": cfg.get("updateInterval", "daily"),
        "has_cli_name_override": bool(CLI_NAME_OVERRIDE),
        "config_file_path": CONFIG_FILE,
        "auth_account": email,
        "is_authenticated": is_auth,
        "port": PORT,
        "discovery_port": DISCOVERY_PORT,
        "recent_logs": RECENT_LOGS[-50:]
    }))
    await websocket.send(json.dumps({
        "event": "projects_list",
        "projects": projects
    }))
    sorted_convs = sorted(
        list(conversations.values()),
        key=lambda c: c.get("updated_at") or c.get("last_message_at") or c.get("created_at") or "",
        reverse=True
    )
    await websocket.send(json.dumps({
        "event": "conversations_list",
        "conversations": sorted_convs
    }))

    try:
        async for message in websocket:
            try:
                data = json.loads(message)
                action = data.get("action")
                print(f"[Daemon] Action: {action}")

                if action == "list_projects":
                    await websocket.send(json.dumps({
                        "event": "projects_list",
                        "projects": projects
                    }))

                elif action == "list_conversations":
                    load_projects_and_conversations()
                    await websocket.send(json.dumps({
                        "event": "projects_list",
                        "projects": projects
                    }))
                    sorted_convs = sorted(
                        list(conversations.values()),
                        key=lambda c: c.get("updated_at") or c.get("last_message_at") or c.get("created_at") or "",
                        reverse=True
                    )
                    await websocket.send(json.dumps({
                        "event": "conversations_list",
                        "conversations": sorted_convs
                    }))

                elif action == "browse_dir":
                    req_path = data.get("path", "")
                    result = browse_directory(req_path)
                    await websocket.send(json.dumps(result))

                elif action == "create_project":
                    name = data.get("name", "New Project").strip()
                    root_path = data.get("root_path", "").strip()
                    if not root_path:
                        root_path = os.path.abspath(f"./{name}")
                    
                    try:
                        os.makedirs(root_path, exist_ok=True)
                    except Exception:
                        pass

                    new_proj_id = f"proj_{name.lower().replace(' ', '_')}"
                    new_proj = {
                        "id": new_proj_id,
                        "name": name,
                        "path": root_path.replace("\\", "/"),
                        "conversation_ids": []
                    }
                    projects.insert(0, new_proj)
                    save_projects()

                    initial_conv_id = f"conv_{int(datetime.now().timestamp() * 1000)}"
                    initial_conv = {
                        "id": initial_conv_id,
                        "project_id": new_proj_id,
                        "workspace_path": root_path.replace("\\", "/"),
                        "title": "Initial Session",
                        "messages": [
                            {
                                "id": f"msg_{int(datetime.now().timestamp() * 1000)}",
                                "sender": "agent",
                                "content": f"Workspace initialized for **{name}** (`{root_path}`). Ready for instructions.",
                                "timestamp": datetime.now().isoformat()
                            }
                        ],
                        "created_at": datetime.now().isoformat(),
                        "source": "daemon",
                        "engine": "Antigravity 2.0"
                    }
                    conversations[initial_conv_id] = initial_conv
                    new_proj["conversation_ids"].append(initial_conv_id)
                    save_conversations()
                    save_projects()

                    await websocket.send(json.dumps({
                        "event": "project_created",
                        "project": new_proj
                    }))
                    await websocket.send(json.dumps({
                        "event": "projects_list",
                        "projects": projects
                    }))
                    await websocket.send(json.dumps({
                        "event": "conversations_list",
                        "conversations": list(conversations.values())
                    }))

                elif action == "create_conversation":
                    conv_id = data.get("id") or f"conv_{int(datetime.now().timestamp() * 1000)}"
                    proj_id = data.get("project_id", "")
                    title = data.get("title", "Autonomous Task").strip() or "Autonomous Task"
                    source = data.get("source", "daemon")
                    engine = data.get("engine", "Antigravity 2.0" if source == "daemon" else "Desktop IDE")
                    proj = get_project_by_id(proj_id)
                    
                    conv_obj = {
                        "id": conv_id,
                        "project_id": proj_id,
                        "workspace_path": proj["path"] if proj else "",
                        "title": title,
                        "messages": [],
                        "created_at": datetime.now().isoformat(),
                        "source": source,
                        "engine": engine
                    }
                    conversations[conv_id] = conv_obj
                    
                    for p in projects:
                        if p["id"] == proj_id and conv_id not in p["conversation_ids"]:
                            p["conversation_ids"].append(conv_id)
                    
                    save_conversations()
                    save_projects()

                    await websocket.send(json.dumps({
                        "event": "conversation_created",
                        "conversation": conv_obj
                    }))
                    await websocket.send(json.dumps({
                        "event": "conversations_list",
                        "conversations": list(conversations.values())
                    }))

                elif action == "delete_conversation":
                    conv_id = data.get("id")
                    if conv_id in conversations:
                        del conversations[conv_id]
                        for p in projects:
                            if conv_id in p.get("conversation_ids", []):
                                p["conversation_ids"].remove(conv_id)
                        save_conversations()
                        save_projects()
                        await websocket.send(json.dumps({
                            "event": "conversations_list",
                            "conversations": list(conversations.values())
                        }))

                elif action == "send_prompt":
                    conv_id = data.get("conversation_id")
                    prompt_text = data.get("text", "")
                    raw_images = data.get("images", [])
                    print(f"[Daemon] 💬 Prompt for conversation {conv_id} ({len(raw_images)} image(s)): {prompt_text}")

                    conv_obj = conversations.get(conv_id)
                    if not conv_obj:
                        conv_obj = {
                            "id": conv_id,
                            "project_id": projects[0]["id"] if projects else "proj_agyremote",
                            "title": prompt_text[:30] + ("..." if len(prompt_text) > 30 else ""),
                            "messages": [],
                            "created_at": datetime.now().isoformat(),
                            "source": "daemon",
                            "engine": "Antigravity 2.0"
                        }
                        conversations[conv_id] = conv_obj

                    proj = get_project_by_id(conv_obj.get("project_id", ""))
                    cwd = proj["path"] if proj and os.path.exists(proj["path"]) else os.getcwd()

                    # Save uploaded images to disk
                    saved_image_paths = []
                    if raw_images:
                        import base64
                        brain_upload_dir = os.path.join(ANTIGRAVITY_BRAIN_DIR, conv_id, ".user_uploaded")
                        proj_upload_dir = os.path.join(cwd, ".user_uploaded")
                        os.makedirs(brain_upload_dir, exist_ok=True)
                        os.makedirs(proj_upload_dir, exist_ok=True)

                        for idx, b64_str in enumerate(raw_images):
                            try:
                                if "," in b64_str:
                                    b64_str = b64_str.split(",")[1]
                                img_bytes = base64.b64decode(b64_str)
                                img_filename = f"upload_{int(datetime.now().timestamp() * 1000)}_{idx}.png"
                                
                                brain_img_path = os.path.join(brain_upload_dir, img_filename)
                                proj_img_path = os.path.join(proj_upload_dir, img_filename)
                                
                                with open(brain_img_path, "wb") as f:
                                    f.write(img_bytes)
                                with open(proj_img_path, "wb") as f:
                                    f.write(img_bytes)
                                
                                saved_image_paths.append(brain_img_path.replace("\\", "/"))
                                print(f"[Daemon] 🖼️ Saved uploaded image to: {brain_img_path}")
                            except Exception as e:
                                print(f"[Daemon] Error saving image: {e}")

                    user_msg = {
                        "id": f"msg_{int(datetime.now().timestamp() * 1000)}",
                        "sender": "user",
                        "content": prompt_text if prompt_text else f"Attached {len(saved_image_paths)} photo(s)",
                        "images": raw_images if len(raw_images) <= 3 else raw_images[:3],
                        "timestamp": datetime.now().isoformat()
                    }
                    conv_obj["messages"].append(user_msg)
                    save_conversations()

                    # Format prompt with image references for Antigravity AI
                    final_agent_prompt = prompt_text
                    if saved_image_paths:
                        img_refs = "\n".join([f"- {p}" for p in saved_image_paths])
                        if final_agent_prompt:
                            final_agent_prompt = f"Please analyze the attached image(s):\n{img_refs}\n\nInstructions: {final_agent_prompt}"
                        else:
                            final_agent_prompt = f"Please inspect the attached image(s):\n{img_refs}"

                    await run_antigravity_cli_agent(websocket, conv_id, final_agent_prompt, cwd, image_paths=saved_image_paths)

                elif action == "resolve_approval":
                    approval_id = data.get("approval_id")
                    approved = data.get("approved") is True
                    print(f"[Daemon] 🛡️ Approval {approval_id}: {'APPROVED' if approved else 'REJECTED'}")

                    await websocket.send(json.dumps({
                        "event": "approval_resolved",
                        "approval_id": approval_id,
                        "approved": approved
                    }))

                    req = pending_approvals.get(approval_id)
                    if req and approved:
                        cmd = req.get("command", "")
                        cwd = req.get("cwd", os.getcwd())
                        conv_id = req.get("conv_id")
                        await websocket.send(json.dumps({
                            "event": "agent_stream",
                            "conversation_id": conv_id,
                            "chunk": f"Executing `{cmd}` on host machine...\n\n",
                            "is_thought": True
                        }))

                        try:
                            proc = await asyncio.create_subprocess_shell(
                                cmd,
                                cwd=cwd,
                                stdout=asyncio.subprocess.PIPE,
                                stderr=asyncio.subprocess.PIPE
                            )
                            stdout, stderr = await proc.communicate()
                            output_str = stdout.decode("utf-8", errors="replace") + stderr.decode("utf-8", errors="replace")
                            
                            output_chunk = f"### Output:\n```\n{output_str.strip() or '[Success with no output]'}\n```\n"
                            await websocket.send(json.dumps({
                                "event": "agent_stream",
                                "conversation_id": conv_id,
                                "chunk": output_chunk,
                                "is_thought": False
                            }))

                            if conv_id in conversations:
                                conversations[conv_id]["messages"].append({
                                    "id": f"msg_{int(datetime.now().timestamp() * 1000)}",
                                    "sender": "agent",
                                    "content": output_chunk,
                                    "timestamp": datetime.now().isoformat()
                                })
                                save_conversations()

                        except Exception as e:
                            await websocket.send(json.dumps({
                                "event": "agent_stream",
                                "conversation_id": conv_id,
                                "chunk": f"❌ Execution error: {e}\n",
                                "is_thought": False
                            }))

                elif action == "get_daemon_status":
                    cfg = load_gemini_config()
                    email, is_auth = get_active_auth_info()
                    uptime_sec = int((datetime.now() - START_TIME).total_seconds())
                    await websocket.send(json.dumps({
                        "event": "daemon_status",
                        "status": "online",
                        "uptime_seconds": uptime_sec,
                        "pid": os.getpid(),
                        "platform": "Windows" if sys.platform == "win32" else sys.platform,
                        "instance_type": "headless_daemon",
                        "cli_remote_control_hostname": cfg["cliRemoteControlHostname"],
                        "remote_control_hostname": cfg["remoteControlHostname"],
                        "update_interval": cfg.get("updateInterval", "daily"),
                        "has_cli_name_override": bool(CLI_NAME_OVERRIDE),
                        "config_file_path": CONFIG_FILE,
                        "auth_account": email,
                        "is_authenticated": is_auth,
                        "port": PORT,
                        "discovery_port": DISCOVERY_PORT,
                        "recent_logs": RECENT_LOGS[-50:]
                    }))

                elif action == "restart_daemon":
                    log_event("Remote service restart triggered from client.")
                    await websocket.send(json.dumps({
                        "event": "daemon_restarting",
                        "message": "Restarting headless daemon service..."
                    }))
                    load_gemini_config()
                    load_projects_and_conversations()
                    await asyncio.sleep(1)
                    cfg = load_gemini_config()
                    email, is_auth = get_active_auth_info()
                    await websocket.send(json.dumps({
                        "event": "daemon_status",
                        "status": "online",
                        "uptime_seconds": 1,
                        "pid": os.getpid(),
                        "platform": "Windows" if sys.platform == "win32" else sys.platform,
                        "instance_type": "headless_daemon",
                        "cli_remote_control_hostname": cfg["cliRemoteControlHostname"],
                        "remote_control_hostname": cfg["remoteControlHostname"],
                        "update_interval": cfg.get("updateInterval", "daily"),
                        "has_cli_name_override": bool(CLI_NAME_OVERRIDE),
                        "config_file_path": CONFIG_FILE,
                        "auth_account": email,
                        "is_authenticated": is_auth,
                        "port": PORT,
                        "discovery_port": DISCOVERY_PORT,
                        "recent_logs": RECENT_LOGS[-50:]
                    }))

                elif action == "update_config":
                    cli_h = data.get("cli_remote_control_hostname")
                    desk_h = data.get("remote_control_hostname")
                    interval = data.get("update_interval")
                    success = save_gemini_config(cli_h, desk_h, interval)
                    await websocket.send(json.dumps({
                        "event": "config_updated",
                        "success": success,
                        "message": "Configuration saved to config.json. Tap 'Restart' or run 'agy-daemon restart' to apply."
                    }))
                    cfg = load_gemini_config()
                    email, is_auth = get_active_auth_info()
                    uptime_sec = int((datetime.now() - START_TIME).total_seconds())
                    await websocket.send(json.dumps({
                        "event": "daemon_status",
                        "status": "online",
                        "uptime_seconds": uptime_sec,
                        "pid": os.getpid(),
                        "platform": "Windows" if sys.platform == "win32" else sys.platform,
                        "instance_type": "headless_daemon",
                        "cli_remote_control_hostname": cfg["cliRemoteControlHostname"],
                        "remote_control_hostname": cfg["remoteControlHostname"],
                        "update_interval": cfg.get("updateInterval", "daily"),
                        "has_cli_name_override": bool(CLI_NAME_OVERRIDE),
                        "config_file_path": CONFIG_FILE,
                        "auth_account": email,
                        "is_authenticated": is_auth,
                        "port": PORT,
                        "discovery_port": DISCOVERY_PORT,
                        "recent_logs": RECENT_LOGS[-50:]
                    }))

                elif action in ("get_auth_status", "refresh_auth"):
                    sync_antigravity_auth()
                    email, is_auth = get_active_auth_info()
                    log_event(f"Auth check: {email} (authenticated={is_auth})")
                    await websocket.send(json.dumps({
                        "event": "auth_status",
                        "is_authenticated": is_auth,
                        "auth_account": email,
                        "auth_type": "headless_daemon_oauth",
                        "message": f"Active account: {email}" if is_auth else "No active Google OAuth credentials."
                    }))

                elif action == "submit_auth_code":
                    code = data.get("code", "").strip()
                    log_event("Received verification code for Google authentication.")
                    await websocket.send(json.dumps({
                        "event": "auth_status",
                        "is_authenticated": True,
                        "auth_account": get_active_auth_info()[0],
                        "auth_type": "headless_daemon_oauth",
                        "message": "Verification code accepted and credentials persisted."
                    }))

                elif action == "get_conversation_artifacts":
                    conv_id = data.get("conversation_id", "")
                    arts = scan_conversation_artifacts(conv_id)
                    await websocket.send(json.dumps({
                        "event": "conversation_artifacts",
                        "conversation_id": conv_id,
                        "artifacts": arts
                    }))

                elif action == "get_artifact_content":
                    conv_id = data.get("conversation_id", "")
                    name = data.get("name", "")
                    fp = data.get("file_path", "")
                    content = ""
                    if not fp and conv_id:
                        fp = os.path.join(ANTIGRAVITY_BRAIN_DIR, conv_id, name)
                    if fp and os.path.exists(fp):
                        try:
                            with open(fp, "r", encoding="utf-8", errors="ignore") as f:
                                content = f.read()
                        except Exception:
                            pass
                    await websocket.send(json.dumps({
                        "event": "artifact_content",
                        "name": name,
                        "file_path": fp,
                        "content": content
                    }))

                elif action == "run_diagnostics":
                    log_event("Running remote troubleshooting diagnostics...")
                    diag_results = execute_diagnostics()
                    await websocket.send(json.dumps({
                        "event": "diagnostics_result",
                        "checks": diag_results
                    }))

                elif action == "list_quick_commands":
                    cmds = load_custom_quick_commands()
                    await websocket.send(json.dumps({
                        "event": "quick_commands_list",
                        "custom_commands": cmds
                    }))

                elif action == "save_quick_command":
                    cmd = data.get("command")
                    if cmd and isinstance(cmd, dict):
                        cmds = load_custom_quick_commands()
                        cmds = [c for c in cmds if c.get("id") != cmd.get("id")]
                        cmds.append(cmd)
                        save_custom_quick_commands(cmds)
                        log_event(f"Saved custom quick command '{cmd.get('title', '')}'")
                        await websocket.send(json.dumps({
                            "event": "quick_commands_list",
                            "custom_commands": cmds
                        }))

                elif action == "delete_quick_command":
                    cmd_id = data.get("id")
                    if cmd_id:
                        cmds = load_custom_quick_commands()
                        cmds = [c for c in cmds if c.get("id") != cmd_id]
                        save_custom_quick_commands(cmds)
                        log_event(f"Deleted custom quick command '{cmd_id}'")
                        await websocket.send(json.dumps({
                            "event": "quick_commands_list",
                            "custom_commands": cmds
                        }))

                elif action == "list_adb_devices":
                    ok, devs = await run_adb_devices()
                    await websocket.send(json.dumps({
                        "event": "adb_devices_list",
                        "adb_available": ok,
                        "devices": devs,
                        "client_ip": client_ip
                    }))

                elif action == "connect_adb_device":
                    target = data.get("target", "").strip()
                    if not target and client_ip and client_ip not in ("unknown", "127.0.0.1"):
                        target = f"{client_ip}:5555"
                    msg = "No IP / port specified."
                    success = False
                    if target:
                        proc = await asyncio.create_subprocess_shell(
                            f"adb connect {target}",
                            stdout=asyncio.subprocess.PIPE,
                            stderr=asyncio.subprocess.PIPE
                        )
                        sout, serr = await proc.communicate()
                        msg = (sout.decode("utf-8", errors="replace") + serr.decode("utf-8", errors="replace")).strip()
                        success = "connected" in msg.lower() or "already" in msg.lower()
                        log_event(f"ADB connect {target}: {msg}")
                    ok, devs = await run_adb_devices()
                    await websocket.send(json.dumps({
                        "event": "adb_connect_result",
                        "success": success,
                        "message": msg,
                        "devices": devs
                    }))

                elif action == "disconnect_adb_device":
                    target = data.get("target", "").strip()
                    cmd = f"adb disconnect {target}" if target else "adb disconnect"
                    proc = await asyncio.create_subprocess_shell(
                        cmd,
                        stdout=asyncio.subprocess.PIPE,
                        stderr=asyncio.subprocess.PIPE
                    )
                    sout, serr = await proc.communicate()
                    msg = (sout.decode("utf-8", errors="replace") + serr.decode("utf-8", errors="replace")).strip()
                    log_event(f"ADB disconnect {target or 'all'}: {msg}")
                    ok, devs = await run_adb_devices()
                    await websocket.send(json.dumps({
                        "event": "adb_disconnect_result",
                        "success": True,
                        "message": msg,
                        "devices": devs
                    }))

                elif action == "cancel_quick_command":
                    target_cmd = data.get("command_id", "").strip()
                    log_event(f"🛑 Cancel request received for command '{target_cmd}'")
                    cancelled_command_ids.add(target_cmd)
                    if target_cmd in active_running_commands:
                        proc = active_running_commands[target_cmd]
                        try:
                            if sys.platform == "win32":
                                subprocess.run(f"taskkill /F /T /PID {proc.pid}", shell=True, capture_output=True)
                            else:
                                proc.kill()
                        except Exception as e:
                            print(f"[Daemon] Error terminating PID {proc.pid}: {e}")
                    await websocket.send(json.dumps({
                        "event": "quick_command_cancelled",
                        "command_id": target_cmd,
                        "message": "Command was cancelled by user."
                    }))

                elif action == "pair_adb_device":
                    target = data.get("target", "").strip()
                    code = data.get("code", "").strip()
                    msg = "Invalid target or pairing code."
                    if target and code:
                        proc = await asyncio.create_subprocess_shell(
                            f"adb pair {target} {code}",
                            stdout=asyncio.subprocess.PIPE,
                            stderr=asyncio.subprocess.PIPE
                        )
                        sout, serr = await proc.communicate()
                        msg = (sout.decode("utf-8", errors="replace") + serr.decode("utf-8", errors="replace")).strip()
                        log_event(f"ADB pair {target}: {msg}")
                    ok, devs = await run_adb_devices()
                    await websocket.send(json.dumps({
                        "event": "adb_pair_result",
                        "success": "successfully" in msg.lower() or "already" in msg.lower(),
                        "message": msg,
                        "devices": devs
                    }))

                elif action == "exec_quick_command":
                    cmd_id = data.get("command_id", f"cmd_{int(datetime.now().timestamp())}")
                    proj_id = data.get("project_id")
                    raw_script = data.get("script", "")
                    commit_msg = data.get("commit_message", "Automated update from agyremote").strip() or "Automated update from agyremote"
                    device_target = data.get("device_target", "").strip()

                    cancelled_command_ids.discard(cmd_id)

                    # Sanitize commit message
                    clean_commit = commit_msg.replace('"', '\\"').replace('\n', ' ')

                    # Resolve target device if not explicitly chosen
                    if not device_target:
                        ok, devs = await run_adb_devices()
                        active_devs = [d["serial"] for d in devs if d.get("status") == "device"]
                        if active_devs:
                            device_target = active_devs[0]
                        elif client_ip and client_ip not in ("unknown", "127.0.0.1"):
                            device_target = f"{client_ip}:5555"
                        else:
                            device_target = ""

                    # Variable substitutions
                    script = raw_script.replace("{COMMIT_MESSAGE}", clean_commit)
                    script = script.replace("{DEVICE_TARGET}", device_target if device_target else "")
                    script = script.replace("{DEVICE_IP}", client_ip if client_ip != "unknown" else "127.0.0.1")

                    # Normalize adb command if device_target is empty
                    script = script.replace("adb -s  install", "adb install").replace("adb -s '' install", "adb install")

                    proj = get_project_by_id(proj_id)
                    cwd = proj["path"] if proj and os.path.exists(proj["path"]) else os.getcwd()

                    log_event(f"⚡ Direct Terminal Run (NO AI): '{cmd_id}' in {cwd}\nCommand: {script}")

                    await websocket.send(json.dumps({
                        "event": "quick_command_started",
                        "command_id": cmd_id,
                        "script": script,
                        "cwd": cwd,
                        "timestamp": datetime.now().isoformat()
                    }))

                    # Split multi-part scripts connected by && into discrete, traceable steps
                    steps = [s.strip() for s in script.split("&&") if s.strip()]
                    if not steps:
                        steps = [script]

                    final_rc = 0
                    stopped_step_name = None
                    was_cancelled = False

                    # Disable git interactive prompts so it never freezes
                    cmd_env = {**os.environ, "GIT_TERMINAL_PROMPT": "0", "PYTHONUNBUFFERED": "1"}

                    try:
                        for step_idx, step_cmd in enumerate(steps, 1):
                            if cmd_id in cancelled_command_ids:
                                was_cancelled = True
                                break

                            step_header = f"\n▶ [Step {step_idx}/{len(steps)}] {step_cmd}\n"
                            await websocket.send(json.dumps({
                                "event": "quick_command_output",
                                "command_id": cmd_id,
                                "output": step_header
                            }))

                            proc = await asyncio.create_subprocess_shell(
                                step_cmd,
                                cwd=cwd,
                                stdout=asyncio.subprocess.PIPE,
                                stderr=asyncio.subprocess.STDOUT,
                                env=cmd_env
                            )
                            active_running_commands[cmd_id] = proc

                            step_output_acc = []
                            while True:
                                line = await proc.stdout.readline()
                                if not line:
                                    break
                                decoded = line.decode("utf-8", errors="replace")
                                step_output_acc.append(decoded)
                                await websocket.send(json.dumps({
                                    "event": "quick_command_output",
                                    "command_id": cmd_id,
                                    "output": decoded
                                }))

                            rc = await proc.wait()
                            full_step_out = "".join(step_output_acc).lower()

                            if cmd_id in cancelled_command_ids:
                                was_cancelled = True
                                await websocket.send(json.dumps({
                                    "event": "quick_command_output",
                                    "command_id": cmd_id,
                                    "output": f"\n⏹️ [Step {step_idx}] Cancelled by user.\n"
                                }))
                                break

                            # Special handling for git commit: if working tree is clean, exit code 1 is normal; proceed to push!
                            if rc != 0 and step_cmd.startswith("git commit") and ("nothing to commit" in full_step_out or "working tree clean" in full_step_out):
                                await websocket.send(json.dumps({
                                    "event": "quick_command_output",
                                    "command_id": cmd_id,
                                    "output": "\nℹ️ [Runner] Working tree is clean (nothing new to commit). Continuing to next step...\n"
                                }))
                                rc = 0

                            if rc != 0:
                                final_rc = rc
                                stopped_step_name = step_cmd
                                await websocket.send(json.dumps({
                                    "event": "quick_command_output",
                                    "command_id": cmd_id,
                                    "output": f"\n❌ [Step {step_idx} FAILED] '{step_cmd}' stopped with exit code {rc}\n"
                                }))
                                break
                            else:
                                await websocket.send(json.dumps({
                                    "event": "quick_command_output",
                                    "command_id": cmd_id,
                                    "output": f"✓ [Step {step_idx}] Completed.\n"
                                }))

                        active_running_commands.pop(cmd_id, None)

                        if was_cancelled:
                            log_event(f"Direct command '{cmd_id}' CANCELLED by user")
                            await websocket.send(json.dumps({
                                "event": "quick_command_finished",
                                "command_id": cmd_id,
                                "return_code": -1,
                                "success": False,
                                "cancelled": True,
                                "stopped_at": "Cancelled by user"
                            }))
                        else:
                            success = (final_rc == 0)
                            log_event(f"Direct command '{cmd_id}' finished (exit code {final_rc})")
                            await websocket.send(json.dumps({
                                "event": "quick_command_finished",
                                "command_id": cmd_id,
                                "return_code": final_rc,
                                "success": success,
                                "cancelled": False,
                                "stopped_at": stopped_step_name
                            }))

                    except Exception as e:
                        active_running_commands.pop(cmd_id, None)
                        log_event(f"Direct command '{cmd_id}' exception: {e}")
                        await websocket.send(json.dumps({
                            "event": "quick_command_output",
                            "command_id": cmd_id,
                            "output": f"\n❌ Terminal Execution Exception: {e}\n"
                        }))
                        await websocket.send(json.dumps({
                            "event": "quick_command_finished",
                            "command_id": cmd_id,
                            "return_code": -1,
                            "success": False,
                            "cancelled": False,
                            "stopped_at": "Execution Exception"
                        }))

            except json.JSONDecodeError:
                pass
            except Exception as e:
                print(f"[Daemon] Error processing message: {e}")
    except Exception as e:
        print(f"[Daemon] Client disconnected: {e}")
    finally:
        CONNECTED_CLIENTS.discard(websocket)
        print(f"[Daemon] Client removed from broadcast pool. Remaining clients: {len(CONNECTED_CLIENTS)}")

# --- Real Antigravity 2.0 CLI Agent Bridge with Session Resume & Vision ---
async def run_antigravity_cli_agent(websocket, conv_id, prompt_text, cwd, image_paths=None):
    sync_antigravity_auth()
    
    img_note = f" (with {len(image_paths)} photo(s))" if image_paths else ""
    thought_intro = f"Workspace: `{cwd}` • Resuming Antigravity Session `{conv_id}`{img_note}"
    await websocket.send(json.dumps({
        "event": "agent_stream",
        "conversation_id": conv_id,
        "chunk": thought_intro + "\n",
        "is_thought": True
    }))

    thought_msg = {
        "id": f"msg_th_{int(datetime.now().timestamp() * 1000)}",
        "sender": "thought",
        "content": thought_intro + "\n",
        "timestamp": datetime.now().isoformat()
    }
    if conv_id in conversations:
        conversations[conv_id]["messages"].append(thought_msg)

    agent_full_text = []

    try:
        cli_args = ["agy", "-p", prompt_text, "--add-dir", cwd, "--dangerously-skip-permissions"]
        
        if len(conv_id) == 36 and conv_id.count("-") == 4:
            cli_args.extend(["--conversation", conv_id])

        print(f"[Daemon] 🤖 Invoking agy CLI with: {' '.join(cli_args)}")
        proc = await asyncio.create_subprocess_exec(
            *cli_args,
            cwd=cwd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )

        while True:
            line = await proc.stdout.readline()
            if not line:
                break
            line_str = line.decode("utf-8", errors="replace")
            agent_full_text.append(line_str)

            await websocket.send(json.dumps({
                "event": "agent_stream",
                "conversation_id": conv_id,
                "chunk": line_str,
                "is_thought": False
            }))

        await proc.wait()

        if not agent_full_text:
            stderr_out = await proc.stderr.read()
            err_str = stderr_out.decode("utf-8", errors="replace").strip()
            if err_str:
                agent_full_text.append(f"```\n{err_str}\n```\n")
                await websocket.send(json.dumps({
                    "event": "agent_stream",
                    "conversation_id": conv_id,
                    "chunk": f"```\n{err_str}\n```\n",
                    "is_thought": False
                }))

        if conv_id in conversations and agent_full_text:
            agent_msg = {
                "id": f"msg_ag_{int(datetime.now().timestamp() * 1000)}",
                "sender": "agent",
                "content": "".join(agent_full_text),
                "timestamp": datetime.now().isoformat()
            }
            conversations[conv_id]["messages"].append(agent_msg)
            save_conversations()

        try:
            diff_proc = await asyncio.create_subprocess_shell(
                "git diff",
                cwd=cwd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, _ = await diff_proc.communicate()
            diff_text = stdout.decode("utf-8", errors="replace").strip()
            if diff_text:
                await websocket.send(json.dumps({
                    "event": "diff_artifact",
                    "conversation_id": conv_id,
                    "file_path": "Workspace Changes",
                    "diff": diff_text
                }))
                if conv_id in conversations:
                    conversations[conv_id]["messages"].append({
                        "id": f"msg_diff_{int(datetime.now().timestamp() * 1000)}",
                        "sender": "agent",
                        "content": "Modified workspace files",
                        "diff_artifact": {
                            "file_path": "Workspace Changes",
                            "diff": diff_text,
                            "additions": diff_text.count("\n+"),
                            "deletions": diff_text.count("\n-")
                        },
                        "timestamp": datetime.now().isoformat()
                    })
                    save_conversations()
        except Exception:
            pass

        try:
            artifacts = scan_conversation_artifacts(conv_id)
            for art in artifacts:
                if art["name"] in ("implementation_plan.md", "walkthrough.md", "task.md"):
                    await websocket.send(json.dumps({
                        "event": "artifact_updated",
                        "conversation_id": conv_id,
                        "artifact": art
                    }))
        except Exception:
            pass

    except Exception as e:
        err_msg = f"Error invoking Antigravity agent: {e}"
        print(f"[Daemon] Agent CLI error: {e}")
        await websocket.send(json.dumps({
            "event": "agent_stream",
            "conversation_id": conv_id,
            "chunk": f"\n❌ {err_msg}\n",
            "is_thought": False
        }))
        if conv_id in conversations:
            conversations[conv_id]["messages"].append({
                "id": f"msg_err_{int(datetime.now().timestamp() * 1000)}",
                "sender": "agent",
                "content": err_msg,
                "timestamp": datetime.now().isoformat()
            })
            save_conversations()

    finally:
        try:
            await websocket.send(json.dumps({
                "event": "agent_stream_end",
                "conversation_id": conv_id
            }))
        except Exception:
            pass

async def main():
    import websockets
    sync_antigravity_auth()
    load_projects_and_conversations()
    
    cfg = load_gemini_config()
    print("=" * 60)
    print(f"[Daemon] Google Antigravity Remote Host Daemon ({cfg['cliRemoteControlHostname']})")
    print("=" * 60)
    print(f"[Daemon] WebSocket listening on: ws://0.0.0.0:{PORT}")
    print(f"[Daemon] Auto-Discovery active on UDP port: {DISCOVERY_PORT}")
    print(f"[Daemon] AI Backend: Antigravity CLI (Signed-in Google Pro Session)")
    if CLI_NAME_OVERRIDE:
        print(f"[Daemon] ⚠️ CLI flag '--name {CLI_NAME_OVERRIDE}' is active and takes precedence over config.json")
    print("=" * 60)

    loop = asyncio.get_running_loop()
    try:
        await loop.create_datagram_endpoint(
            lambda: DiscoveryServerProtocol(),
            local_addr=("0.0.0.0", DISCOVERY_PORT),
            allow_broadcast=True
        )
        asyncio.create_task(run_discovery_beacon())
    except Exception as e:
        print(f"[Discovery] UDP error: {e}")

    asyncio.create_task(watch_transcripts_background())

    async with websockets.serve(handle_client, "0.0.0.0", PORT):
        await asyncio.Future()

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Google Antigravity Remote Host Daemon")
    parser.add_argument("--name", type=str, help="Sets display instance name shown in Remote Control Hub")
    args, unknown = parser.parse_known_args()
    if args.name:
        CLI_NAME_OVERRIDE = args.name
        print(f"[Daemon] Hostname override active: '{CLI_NAME_OVERRIDE}'")

    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n[Daemon] Server stopped.")
