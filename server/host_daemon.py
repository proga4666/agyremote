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

projects = []
conversations = {}
pending_approvals = {}

def clean_transcript_text(text):
    if not text:
        return ""
    cleaned = re.sub(r"<ADDITIONAL_METADATA>.*?</ADDITIONAL_METADATA>", "", text, flags=re.DOTALL)
    cleaned = re.sub(r"<SYSTEM_MESSAGE>.*?</SYSTEM_MESSAGE>", "", cleaned, flags=re.DOTALL)
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

                        if stype == "USER_INPUT" and content:
                            clean_text = clean_transcript_text(content)
                            if clean_text:
                                if not first_user_prompt:
                                    first_user_prompt = clean_text
                                messages.append({
                                    "id": f"msg_{len(messages)}_{conv_id[:8]}",
                                    "sender": "user",
                                    "content": clean_text,
                                    "timestamp": step.get("timestamp") or mtime
                                })

                        elif stype == "PLANNER_RESPONSE" and content:
                            messages.append({
                                "id": f"msg_{len(messages)}_{conv_id[:8]}",
                                "sender": "agent",
                                "content": content,
                                "timestamp": step.get("timestamp") or mtime
                            })

                    except json.JSONDecodeError:
                        continue

            if messages:
                title = official_titles.get(conv_id) or extract_fallback_title(brain_dir, first_user_prompt, conv_id)
                
                discovered_convs[conv_id] = {
                    "id": conv_id,
                    "project_id": proj_id,
                    "workspace_path": ws_path,
                    "title": title,
                    "messages": messages,
                    "created_at": mtime,
                    "is_pc_synced": True
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

    # Sort projects: active/most populated first
    projects = sorted(discovered_projects.values(), key=lambda p: len(p["conversation_ids"]), reverse=True)
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
                reply = json.dumps({
                    "service": "antigravity_daemon",
                    "host_name": os.environ.get("COMPUTERNAME", "Workstation PC"),
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
    
    beacon_data = json.dumps({
        "service": "antigravity_daemon",
        "host_name": os.environ.get("COMPUTERNAME", "Workstation PC"),
        "port": PORT,
        "version": "2.0"
    }).encode("utf-8")

    while True:
        try:
            sock.sendto(beacon_data, ("255.255.255.255", DISCOVERY_PORT))
        except Exception:
            pass
        await asyncio.sleep(2.5)

# --- Client Handler ---
async def handle_client(websocket):
    client_ip = websocket.remote_address[0] if websocket.remote_address else "unknown"
    print(f"\n[Daemon] Mobile client connected from {client_ip}")

    # Re-sync on connect
    load_projects_and_conversations()

    await websocket.send(json.dumps({
        "event": "status_notice",
        "message": f"Connected to Host Workstation ({os.environ.get('COMPUTERNAME', 'PC')})"
    }))
    await websocket.send(json.dumps({
        "event": "projects_list",
        "projects": projects
    }))
    await websocket.send(json.dumps({
        "event": "conversations_list",
        "conversations": list(conversations.values())
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
                    await websocket.send(json.dumps({
                        "event": "conversations_list",
                        "conversations": list(conversations.values())
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
                        "created_at": datetime.now().isoformat()
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
                    proj = get_project_by_id(proj_id)
                    
                    conv_obj = {
                        "id": conv_id,
                        "project_id": proj_id,
                        "workspace_path": proj["path"] if proj else "",
                        "title": title,
                        "messages": [],
                        "created_at": datetime.now().isoformat()
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
                            "created_at": datetime.now().isoformat()
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

            except json.JSONDecodeError:
                pass
            except Exception as e:
                print(f"[Daemon] Error processing message: {e}")

    except Exception as e:
        print(f"[Daemon] Client disconnected: {e}")

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

    except Exception as e:
        print(f"[Daemon] agy execution error: {e}")
        err_msg = f"❌ Antigravity Agent Error: {e}\n"
        await websocket.send(json.dumps({
            "event": "agent_stream",
            "conversation_id": conv_id,
            "chunk": err_msg,
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
    
    print("=" * 60)
    print("[Daemon] Google Antigravity Remote Host Daemon (agy-daemon)")
    print("=" * 60)
    print(f"[Daemon] WebSocket listening on: ws://0.0.0.0:{PORT}")
    print(f"[Daemon] Auto-Discovery active on UDP port: {DISCOVERY_PORT}")
    print(f"[Daemon] AI Backend: Antigravity CLI (Signed-in Google Pro Session)")
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

    async with websockets.serve(handle_client, "0.0.0.0", PORT):
        await asyncio.Future()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n[Daemon] Server stopped.")
