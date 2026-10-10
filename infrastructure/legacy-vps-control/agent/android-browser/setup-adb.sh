#!/data/data/com.termux/files/usr/bin/bash
# Pair Android's own Wireless Debugging with ADB in Termux.
# Does not upload ports, pairing code, URLs, cookies or credentials to GitHub.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
echo "KATARINA Chrome Android setup — only for your own authorized phone."
echo "1. Settings > Developer options > Wireless debugging: ON"
echo "2. Select Pair device with pairing code and KEEP THAT DIALOG OPEN."
echo "3. Use the IP:PORT shown in the pairing dialog (not the main debug port)."
command -v adb >/dev/null || { echo "Missing adb: pkg install android-tools -y"; exit 1; }
command -v curl >/dev/null || { echo "Missing curl: pkg install curl -y"; exit 1; }
command -v node >/dev/null || { echo "Missing Node.js: pkg install nodejs-lts -y"; exit 1; }
echo
read -r -p 'Pairing IP:PORT (as shown on Android): ' pair_addr
if [[ ! "$pair_addr" =~ ^[0-9.]+:[0-9]{2,5}$ ]]; then
 echo "Invalid pairing address; stop and check Android settings." >&2; exit 1
fi
echo "Type the Android pairing code ONLY into the ADB prompt. Never send it to chat/GitHub."
adb pair "$pair_addr"
echo
echo "4. Close the pairing-code dialog, return to main Wireless debugging page."
echo "5. Copy the separate IP:PORT shown under Wireless debugging."
read -r -p 'Main debugging IP:PORT: ' debug_addr
if [[ ! "$debug_addr" =~ ^[0-9.]+:[0-9]{2,5}$ ]]; then
 echo "Invalid debugging address" >&2; exit 1
fi
adb connect "$debug_addr"
echo "Connected devices:"
adb devices -l
echo
echo "Launching Chrome manually on your phone is recommended before the next step."
echo "Forwarding CDP to a LOCAL port only (127.0.0.1:9222, never public internet)."
adb forward tcp:9222 localabstract:chrome_devtools_remote
if curl -fsS --max-time 4 http://127.0.0.1:9222/json/version >/dev/null; then
  echo "PASS: Chrome Android CDP can be reached from Termux."
else
  echo "Chrome CDP unavailable. Open Chrome, check Wireless debugging and adb devices."
  echo "The GitHub-Termux control bridge still works independently."
fi
echo
echo "Installing free playwright-core package (no browser download/paid API)..."
cd "$ROOT/agent/android-browser"
npm install --ignore-scripts --no-audit --no-fund --omit=optional
echo "Read-only Playwright test:"
node browser-probe.js || true
echo
echo "Done. Keep Wireless debugging local; never expose port 9222 to LAN/public internet."
