# KATARINA Android Browser Bridge (no paid browser credits)

**Purpose:** Inspect whether the owner's Android Chrome is reachable locally from Termux, then check whether Playwright can attach. This stage does **not** submit any job bids, accept contracts, click elements, or transmit personal URLs, cookies, OTPs, or browser content to GitHub.

## Design
`ChatGPT (GitHub connector) -> existing private Katarina-VPS-Control -> TermuxAgent.py -> fixed, allowlisted local browser-probe.js -> adb 127.0.0.1:9222 -> Chrome Android`.

The Windows VPS uses the same `connection.json` but does not process Termux-targeted jobs. No Android device is presently paired.

## Step A — register Termux on the existing bridge
Install up-to-date Termux (trusted F-Droid build, not conflicting store variants), open the Termux terminal:

```sh
pkg update -y
pkg install git python nodejs-lts android-tools curl openssh tmux gh -y
gh auth login
gh auth setup-git
git clone https://github.com/alfaaulia8-sys/Katarina-VPS-Control.git ~/Katarina-VPS-Control
cd ~/Katarina-VPS-Control
bash agent/install-termux.sh
```

Authorize GitHub in the phone's own browser. Never send verification codes, tokens or passwords to ChatGPT. If `gh` is unavailable through `pkg`, arrange approved SSH authentication for this single private repository before cloning.

Wait for `status/termux.json` and `results/termux-connection-check.termux.json` to appear in the existing GitHub repo. That confirms basic connectivity. Start polling:

```sh
cd ~/Katarina-VPS-Control
tmux new-session -d -s katarina-bridge 'python agent/TermuxAgent.py'
```

To see activity, `tmux attach -t katarina-bridge`. Android battery optimization may pause/stop this session.

## Step B — connect the user's own Chrome (Android 11+ wireless debugging)
1. In Android Settings > About phone, enable Developer Options if necessary.
2. In Developer Options, enable **Wireless debugging** (phone must be connected to Wi-Fi).
3. Open **Pair device with pairing code**, and note the pairing address `IP:PORT`. Leave that dialog open.
4. In Termux, after the repository is cloned:
   ```sh
   cd ~/Katarina-VPS-Control
   bash agent/android-browser/setup-adb.sh
   ```
5. The script prompts for **pairing IP:PORT** and lets `adb pair` prompt for the code. Enter the code inside Termux only.
6. Return to main Wireless debugging screen. Enter its **separate debugging IP:PORT** when the script asks.
7. Open Chrome on the phone. The script runs `adb forward tcp:9222 localabstract:chrome_devtools_remote` and checks the local CDP socket.
8. `npm install` runs in the local probe folder and installs **playwright-core only**, not a paid service or downloadable Chromium browser binary.
9. `node browser-probe.js` prints whether Chrome CDP and Playwright can attach. No page content is collected or uploaded.

**Compatibility:** Playwright Android is experimental. Some devices / Android vendor builds prevent Termux-local ADB pairing, and some CDP sessions do not support Playwright `connectOverCDP`. If the script reports `cdp_connected_but_playwright_android_not_supported_on_this_device`, keep the functional GitHub-Termux bridge and troubleshoot with official Playwright Android `_android` support or a standard local desktop host. Do not claim remote Chrome control before a successful probe.

## Test once locally
```sh
cd ~/Katarina-VPS-Control
node agent/android-browser/browser-probe.js
```

You should see JSON booleans like `cdp_available` and `playwright_connected`; never send full URLs or OTPs.

## Security / disconnect
Keep debugging attached to the phone and loopback. Never expose TCP 9222 to the public internet or create a remotely callable, arbitrary-JavaScript job handler. Job actions are allowlisted.
To disconnect the browser:
```sh
adb forward --remove tcp:9222
adb disconnect
```
Then switch off Wireless debugging in Android Settings. The GitHub connection to Termux remains independent.

### Cost
Open-source script, Playwright-core, ADB, Termux and GitHub under an eligible free-tier account have no browser-per-credit fees. Normal mobile data, electricity and any platform-specific fees may still apply.
