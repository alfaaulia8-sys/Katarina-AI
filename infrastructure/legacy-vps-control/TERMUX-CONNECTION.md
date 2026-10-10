# KATARINA — one connection for VPS and Android Termux

**The existing private GitHub repository is the single connection bridge.** Do not create a second control repository or copy VPS browser cookies, passwords, personal access tokens, or SSH private keys to the phone.

## Shared configuration
- `connection.json` contains both `devices.vps` and `devices.termux`.
- `jobs/*.json` is the single job queue.
- `results/*.json` and `status/{vps,termux}.json` contain the results and heartbeats.
- Every job **must specify `target`**. Older jobs without a target remain VPS-only.
- The VPS agent only processes `target: "vps"` or legacy un-targeted jobs.
- The Termux agent only processes `target: "termux"` or `target: "android"`.
- A job can request only documented allowlisted actions, not arbitrary shell commands.

## Existing VPS
The existing Windows Scheduled Task `KatarinaVPSControlAgent` continues to run `agent/KatarinaVPSAgent.ps1`. Do not install a second VPS agent.

## Termux first-time setup (on the user's Android phone)
1. Install Termux from F-Droid or another trusted distribution.
2. In Termux:
   ```sh
   pkg update
   pkg install git python openssh tmux gh -y
   gh auth login
   gh auth setup-git
   git clone https://github.com/alfaaulia8-sys/Katarina-VPS-Control.git ~/Katarina-VPS-Control
   cd ~/Katarina-VPS-Control
   bash agent/install-termux.sh
   ```
3. When `--once` reports success, start the Termux agent:
   ```sh
   cd ~/Katarina-VPS-Control
   tmux new-session -d -s katarina-bridge 'python agent/TermuxAgent.py'
   ```
4. Keep Termux allowed to run in the background. Battery optimizations can stop the polling process. The login to GitHub must be an authorized account with write access. Do **not** paste tokens into ChatGPT.
5. Verify `status/termux.json` was pushed to the **same** GitHub repository. Until that file exists and is fresh, the phone is not connected.

Note: `gh` installation and browser-based login depend on the Termux device and package availability. If `pkg install gh` fails, use a dedicated SSH deploy key with write permissions for this repository only; never reuse the VPS key.

## Test jobs
Termux:
```json
{"target":"termux","action":"status","requested_by":"chatgpt"}
```
VPS:
```json
{"target":"vps","action":"status","requested_by":"chatgpt"}
```
Save them under different unique filenames in `jobs/`. The job runners avoid replaying IDs.

## Chrome Android (separate, local-only permission)
The `chrome_tabs` action checks `127.0.0.1:9222` on the phone *only when the user has enabled local ADB forwarding*. It returns tab counts and hostnames, never cookies or complete URLs. It cannot log in, bid, or bypass CAPTCHA and does not expose port 9222 to the internet.

Supported Termux actions: `status`, `agent_capabilities`, `chrome_tabs`.

## Safety / limitations
- Authentication for Termux has to be completed on the phone; GitHub connector access here **does not** automatically authenticate Termux.
- Do not use the bridge to send arbitrary code or credential/OTP harvest jobs.
- Platform-specific automated bidding must be compliant with site policy.
- Status here is configured / prepared, **not connected**, until the Termux heartbeat arrives.

## NEW: Local Chrome Android / Playwright path
Chrome access is a separate, optional step after the GitHub-Termux bridge is confirmed.
See [agent/android-browser/README.md](agent/android-browser/README.md).

After cloning and starting the Termux agent, run:
```sh
cd ~/Katarina-VPS-Control
bash agent/android-browser/setup-adb.sh
```
This pairs Wireless debugging on the same Android device, checks the localhost Chrome CDP socket, and optionally installs free `playwright-core`. Android browser support is experimental: being logged into GitHub does not automatically give access to Chrome. No job bidding or contracts are authorized by this probe.