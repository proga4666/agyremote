Here is the complete documentation for the **Install Remote Control headless daemon** section from the official Google Antigravity documentation.

---

# Antigravity Remote Control: Headless Daemon Documentation

## 1. Overview
The **Antigravity Remote Control Headless Daemon** (`agy-daemon`) allows you to run Google Antigravity as a background service on remote machines (such as cloud VMs, headless Linux/Windows servers, or build nodes) without needing a desktop graphical interface or active display.

By connecting through the web-based **Antigravity Remote Control Dashboard**, you can drive agent sessions, initiate multi-step refactoring/build tasks, inspect plans, and review artifacts running on remote environments from any web browser or mobile device.

---

## 2. Installation Instructions

### Linux and macOS
Run the automated installation script in your terminal:

```bash
curl -fsSL https://antigravity.google/cli/agy-daemon.sh | bash
```

To pass optional flags (such as setting an instance name or update schedule during setup), append `bash -s --`:

```bash
curl -fsSL https://antigravity.google/cli/agy-daemon.sh | bash -s -- install --name "my-box"
```

---

### Windows
> **Important:** On Windows, you **must run the command from an Administrator Command Prompt (`cmd.exe`)**, not PowerShell.

Open Command Prompt as Administrator ("Run as administrator") and run:

```cmd
curl -fsSL https://antigravity.google/cli/agy-daemon.cmd -o agy-daemon.cmd && agy-daemon.cmd install
```

*Note: While `install` and `uninstall` require an Administrator prompt, `status` and `restart` can be executed from a standard command prompt.*

---

## 3. Command Options and Service Management

Both the shell script (`agy-daemon.sh`) and Windows batch script (`agy-daemon.cmd`) accept the following options:

### Installation Flags
| Flag | Description | Default |
| :--- | :--- | :--- |
| `install --name "<name>"` | Sets the display instance name shown in the Remote Control Hub. | Auto-generated friendly name |
| `install --interval <interval>` | Sets how frequently automatic updates are checked and applied (`daily`, `weekly`). | `daily` |
| `install --no-auto-update` | Disables automatic updates entirely. | Enabled |
| `install --no-prompt` | Non-interactive mode (skips interactive prompts; ideal for CI/CD and automated provisioning scripts). | Interactive |

### Service Management Commands
```bash
# Check daemon status and inspect recent activity logs
agy-daemon status

# Restart the service (this also applies any pending updates)
agy-daemon restart

# Remove and uninstall the headless service
agy-daemon uninstall
```
*(On Linux/macOS, substitute with `./agy-daemon.sh <command>` or run via the installed wrapper; on Windows, use `agy-daemon.cmd <command>`)*

---

## 4. One-Time Sign-In / Authentication

1. During setup, the installer prints an authentication URL in the terminal.
2. Open the URL in your browser, sign in with your Google Account, and copy the verification code.
3. Paste the verification code back into the terminal.

* **Persistence:** Once authenticated, the daemon stores the credentials and handles reconnection automatically across reboots.
* **Separation of Concerns:** Headless daemon authentication is maintained separately from the Antigravity desktop editor. If you ever sign out of the `agy` CLI on that system, the daemon will lose access; re-running the installation script re-establishes the connection.

---

## 5. Naming Your Machine

The instance name is how your headless server appears in the Remote Control switcher interface. There are three ways to configure it:

1. **During Interactive Setup:** The script prompts for a name. Press `Enter` to keep the default friendly generated name (e.g., `my-machine-distant-plume`).
2. **Via Command Line Flag:** Pass `--name "<custom-name>"` to the install command.
3. **By Editing the Config File:**
   - Update the `cliRemoteControlHostname` property in the configuration file.
   - Run `agy-daemon restart` to apply changes (changes do not take effect while the service is actively running).

> **Precedence Warning:** If you installed using `--name`, that parameter takes precedence and overwrites manual configuration file edits each time the daemon restarts. To make manual config file edits permanent, re-run setup and leave the name prompt blank.

---

## 6. Settings File Locations

| Platform | Configuration File Path |
| :--- | :--- |
| **Linux / macOS** | `~/.gemini/config/config.json` |
| **Windows** | `%USERPROFILE%\.gemini\config\config.json` |

### Key Configuration Fields
* `cliRemoteControlHostname`: Configures the instance name for the **headless daemon service**.
* `remoteControlHostname`: Configures the instance name for the **desktop Antigravity editor** on the same machine.

---

## 7. Service Lifecycle Matrix

How the headless daemon behaves across operating systems:

| Behavior | Linux | macOS | Windows |
| :--- | :--- | :--- | :--- |
| **Starts at system boot (no user login needed)** | **Yes** | No (starts upon user login) | **Yes** |
| **Keeps running after user logout** | **Yes** | No (resumes at next login) | **Yes** |
| **Recovers automatically after crash** | **Yes** | **Yes** | No (recovers on next boot, scheduled update, or manual restart) |

---

## 8. Troubleshooting

* **Machine does not appear in the Remote Control Hub:**
  * Run `agy-daemon status` and review the output logs.
  * If token or sign-in errors are logged, re-run the setup script to refresh authentication.
  * Ensure outbound network connectivity to Google services is unimpeded.
* **Rename didn't take effect:**
  * The daemon only reads its hostname at initialization. Run `agy-daemon restart`.
* **Hostname keeps reverting back after editing `config.json`:**
  * The daemon was installed with the `--name` flag. Re-run setup and leave the name prompt empty to restore configuration-file authority.
* **Windows installation fails:**
  * Ensure you are running standard **Command Prompt (`cmd.exe`) as Administrator**. PowerShell is not supported for installation/uninstallation scripts.
* **Duplicate entries appear in the Remote Control Hub:**
  * One entry corresponds to the desktop IDE (`remoteControlHostname`) and the other to the headless daemon (`cliRemoteControlHostname`). You can rename them separately in their respective settings to distinguish them.
  