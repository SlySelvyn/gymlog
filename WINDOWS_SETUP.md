# Developing iPhone Apps on a Windows PC — Complete Setup Guide

_For the GymLog project · VS Code-centric · Last updated 2026-07-20_

---

## 0. The honest reality check (read this first)

Apple does not support iOS development on Windows. There is no Windows version of
Xcode, and four things are **Mac-only, full stop**:

| Task | Mac required? |
|---|---|
| Writing & testing pure Swift logic (our `CoreLogic` package) | ❌ No — works on Windows/WSL |
| Building the full iOS app & installing it on your iPhone | ⚠️ Mostly no — possible via **xtool** (Path B) with limitations |
| iOS **Simulator** | ✅ Yes — macOS only |
| Some entitlements, app extensions, full debugging | ✅ Yes (Xcode) |
| **App Store submission** (archive, notarize, upload) | ✅ Yes — must run through Xcode/altool on macOS at least once per release |

So the strategy is a **hybrid**: do 90% of daily development on your Windows PC
(Paths A + B below), and use a cheap/rented Mac (Path C) or CI (Path D) for the
Simulator, polish, and App Store releases. You will need **a Mac of some form by
Month 5–6** of the roadmap (paywall/StoreKit testing + App Store submission).

You will also need, regardless of path:
- An **Apple ID** (free). Free accounts can sign apps onto your own iPhone, but
  the install expires every **7 days** and allows max 3 sideloaded apps.
- Eventually the **Apple Developer Program** ($99/yr) — removes the 7-day limit,
  enables TestFlight, App Store, and the App Intents/Action Button experience
  behaving properly on a distributed build.
- **An actual iPhone** for testing. For this app specifically: mic capture,
  on-device speech recognition, and the Action Button do not exist in the
  Simulator — a physical device (iPhone 15 Pro+ for the Action Button) is the
  real test target anyway. This softens the "no Simulator on Windows" problem a lot.

---

## 1. Overview of the four paths

| Path | What it gives you | Cost | Effort |
|---|---|---|---|
| **A. WSL2 + Swift toolchain** | Build & unit-test `CoreLogic` (parser, analytics, export) with fast iteration | Free | 30 min |
| **B. xtool (in WSL2)** | Build the **actual iOS app**, sign it, and install it on your USB-connected iPhone — from Windows | Free | 1–2 hrs |
| **C. Cloud / remote Mac + VS Code Remote-SSH** | Full Xcode: Simulator, debugging, profiling, App Store | ~$20–50/mo rented, or ~$300–500 one-time used M1 Mac mini | 1 hr |
| **D. GitHub Actions macOS runners** | Automated builds + TestFlight uploads without touching a Mac | Free tier (2,000 min/mo; macOS minutes count 10×) | 2–3 hrs once |

Recommended combo for this project: **A today, B this week, C or D by Month 3
(TestFlight alpha), a real Mac by Month 6 (launch).**

---

## 2. Path A — WSL2 + Swift toolchain (do this first)

This is where the GymLog parser/normalizer/analytics work happens daily.

### 2.1 Install WSL2 + Ubuntu 24.04

Open **PowerShell as Administrator**:

```powershell
wsl --install -d Ubuntu-24.04
```

Reboot if asked, launch "Ubuntu 24.04" from the Start menu, create a username/
password. Verify you're on WSL **2**:

```powershell
wsl -l -v        # VERSION column should say 2
```

### 2.2 Install Swift inside Ubuntu

The cleanest installer is **swiftly** (the official Swift toolchain manager):

```bash
# inside the Ubuntu terminal
sudo apt update && sudo apt install -y curl gnupg build-essential \
    libcurl4-openssl-dev libxml2-dev libsqlite3-dev pkg-config \
    binutils git unzip zip

curl -O https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz
tar zxf swiftly-$(uname -m).tar.gz
./swiftly init
source ~/.local/share/swiftly/env.sh      # add to ~/.bashrc too
swiftly install latest
swift --version                            # should print Swift 6.x
```

(If swiftly gives you trouble, the fallback is the plain tarball from
<https://www.swift.org/install/linux/> — download, extract, add `usr/bin` to PATH.
That's exactly how this project's tests were verified.)

### 2.3 Get the project into WSL and run the tests

Your Windows drive is mounted at `/mnt/c` inside WSL, so you can work directly on
your existing folder:

```bash
cd "/mnt/c/Users/sly/Desktop/gym app proj/GymLog/CoreLogic"
swift test
```

> **Performance tip:** builds are noticeably faster if the code lives on the
> Linux filesystem. Consider cloning/moving the repo to `~/gymlog` inside WSL and
> pushing to GitHub as the sync point between environments.

Expected output today: `Executed 38 tests, with 0 failures`.

---

## 3. VS Code setup (works for Paths A, B, and C)

### 3.1 Extensions to install

| Extension | ID | Why |
|---|---|---|
| **WSL** | `ms-vscode-remote.remote-wsl` | Open folders inside WSL with full toolchain access |
| **Swift** | `swiftlang.vscode-swift` | Official Swift extension: syntax, SourceKit-LSP autocomplete/jump-to-definition, test explorer, debugging |
| **CodeLLDB** | `vadimcn.vscode-lldb` | Debugger backend the Swift extension uses |
| **Remote-SSH** | `ms-vscode-remote.remote-ssh` | For Path C (cloud Mac) |
| **GitHub Actions** | `github.vscode-github-actions` | For Path D pipelines |

### 3.2 Connect VS Code to WSL

1. Open VS Code on Windows.
2. `Ctrl+Shift+P` → **"WSL: Connect to WSL"**.
3. File → Open Folder → the `GymLog` directory.
4. The Swift extension detects `CoreLogic/Package.swift` automatically: you get
   autocomplete across the whole package, inline errors, and a **Testing** sidebar
   where every parser test appears with a run/debug button.

### 3.3 Handy tasks

Create `.vscode/tasks.json` in the repo:

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Swift: test CoreLogic",
      "type": "shell",
      "command": "swift test",
      "options": { "cwd": "${workspaceFolder}/CoreLogic" },
      "group": { "kind": "test", "isDefault": true },
      "problemMatcher": []
    },
    {
      "label": "xtool: build & install on iPhone",
      "type": "shell",
      "command": "xtool dev",
      "options": { "cwd": "${workspaceFolder}" },
      "problemMatcher": []
    }
  ]
}
```

`Ctrl+Shift+B` / `Ctrl+Shift+P → Run Test Task` now runs the corpus.

---

## 4. Path B — xtool: build the real iOS app from Windows

**xtool** (<https://github.com/xtool-org/xtool>) is an open-source, SwiftPM-based
Xcode replacement that runs on Linux/WSL. It can build a SwiftPM package into a
signed `.ipa` and install it on your USB-connected iPhone. This is how you get
the actual GymLog app onto your phone without a Mac.

### 4.1 What you need

- WSL2 Ubuntu from Path A.
- An **Apple ID** (xtool talks to Apple Developer Services to create a free
  signing certificate).
- A **copy of `Xcode.xip`** downloaded from Apple
  (<https://developer.apple.com/download/all/> — sign in with the Apple ID,
  download the latest Xcode). You are not running Xcode; xtool only extracts the
  **iOS SDK** (headers + frameworks) from it. It's a ~3–4 GB download — put it
  somewhere WSL can see, e.g. `/mnt/c/Users/sly/Downloads/Xcode.xip`.
- **usbipd-win** so WSL can see your iPhone over USB:

```powershell
# PowerShell (admin), on Windows:
winget install usbipd
# plug in the iPhone, then:
usbipd list                      # find the BUSID of "Apple iPhone"
usbipd bind --busid <BUSID>
usbipd attach --wsl --busid <BUSID>
```

```bash
# inside WSL — device services:
sudo apt install -y usbmuxd libimobiledevice-utils
idevice_id -l                    # should print your iPhone's UDID
```

### 4.2 Install and set up xtool

Follow the current install guide at
<https://xtool-org.github.io/xtool/> (it evolves quickly). The flow is:

```bash
# inside WSL
xtool setup
#  → prompts for the path to Xcode.xip (extracts the Darwin SDK)
#  → prompts for your Apple ID to set up signing
xtool devices                    # confirm the iPhone is visible
```

### 4.3 GymLog and xtool

xtool builds **SwiftPM-defined apps** (`xtool new` scaffolds one with an
`xtool.yml`). To use it with this repo:

```bash
cd ~/gymlog          # repo root
xtool new GymLogApp  # generates the SwiftPM app shell + xtool.yml
# then: point its Package.swift at ../CoreLogic as a local dependency,
# and move the iOSApp/*.swift sources into Sources/GymLogApp/
xtool dev            # builds, signs, installs to the connected iPhone
```

### 4.4 Honest limitations of Path B (why a Mac still matters later)

- **Free Apple ID signing expires every 7 days** — re-run `xtool dev` to refresh.
  A paid developer account extends this to a year.
- **App extensions and many entitlements aren't supported yet.** Our MVP mostly
  avoids these (App Intents live in the main app bundle), but treat anything
  Action-Button-related as "verify on device, fall back to in-app mic if odd."
- **No debugger attach out of the box** — you get `print`/`os_log` + the device
  console. Real LLDB debugging = Path C.
- **No Simulator** on Windows. Physical iPhone only (fine for this app).
- Sole-maintainer project: pin the version that works and upgrade deliberately.

If xtool proves fiddly, skip to Path C for the app target and keep Windows for
CoreLogic — the project structure was designed so that split is painless.

---

## 5. Path C — a real Mac, driven from your Windows PC

When you want the Simulator, LLDB, Instruments, StoreKit testing, or App Store
submission.

### 5.1 Hardware options, cheapest-first

| Option | Cost | Notes |
|---|---|---|
| **Used Mac mini M1 (2020), 8 GB** | ~$250–400 one-time | Fully supports current Xcode. Best value; sits headless on your network. |
| **Cloud Mac** — MacStadium, Scaleway, MacinCloud, AWS EC2 `mac2` | ~$20–100/mo (AWS bills a 24 h minimum per allocation) | Zero hardware; pay while you need it. |
| New Mac mini M4 | ~$599 | If you decide to commit. |

### 5.2 Drive it from VS Code on Windows

1. On the Mac: System Settings → General → Sharing → enable **Remote Login** (SSH).
2. Install Xcode (App Store) + command-line tools: `xcode-select --install`.
3. On Windows VS Code: **Remote-SSH: Connect to Host** → `you@mac-mini.local`.
4. Open the repo (clone it on the Mac; sync via Git).
5. Build/run from the integrated terminal:

```bash
# list simulators / devices
xcrun simctl list devices
# build the app for a simulator
xcodebuild -scheme GymLog -destination 'platform=iOS Simulator,name=iPhone 16' build test
# or install to a USB/Wi-Fi device
xcodebuild -scheme GymLog -destination 'platform=iOS,name=Sly's iPhone' build
```

6. Optional quality-of-life: the **SweetPad** VS Code extension (`sweetpad.sweetpad`)
   wraps xcodebuild/simulators/devices in a friendly VS Code UI, so the whole
   Xcode loop happens inside VS Code. You only open Xcode.app itself for signing
   wizardry, asset catalogs, and App Store archives.
7. For seeing the Simulator/GUI remotely: macOS Screen Sharing (VNC — connect
   with TightVNC/RealVNC from Windows) or Jump Desktop.

### 5.3 One-time Xcode project creation

Do this once on the Mac (10 minutes) — after that, all edits are just files:

1. Xcode → New Project → iOS App → SwiftUI → name **GymLog**, iOS 17 minimum.
2. File → Add Package Dependencies → **Add Local…** → select `CoreLogic/`.
3. Drag the `iOSApp/` folders into the target.
4. Info tab → add `NSSpeechRecognitionUsageDescription` and
   `NSMicrophoneUsageDescription` strings.
5. Signing & Capabilities → select your team.
6. `⌘R` on your plugged-in iPhone. On the phone: Settings → Action Button →
   Shortcut → **Log a Set**.

---

## 6. Path D — CI on GitHub Actions (Mac-less TestFlight)

GitHub's free tier includes macOS runners (macOS minutes burn the free pool at
10×, so keep jobs lean). This gives you signed TestFlight builds triggered by
`git push`, with no Mac in the room.

Minimal `.github/workflows/ios.yml`:

```yaml
name: iOS build
on: [push]
jobs:
  core-tests:
    runs-on: ubuntu-latest          # cheap: parser corpus on Linux
    steps:
      - uses: actions/checkout@v4
      - uses: swift-actions/setup-swift@v2
      - run: swift test --package-path CoreLogic

  app-build:
    runs-on: macos-15               # 10× minutes — only on main
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v4
      - run: xcodebuild -scheme GymLog -destination 'generic/platform=iOS' \
             -archivePath GymLog.xcarchive archive CODE_SIGNING_ALLOWED=NO
```

For signing + TestFlight upload, add **fastlane** (`match` for certificates,
`pilot` for upload) once you have the $99 developer account. That is the standard
"Windows developer ships iOS app" pipeline: code on Windows → push → CI Mac
builds → TestFlight on your phone.

---

## 7. Optional: Swift natively on Windows (no WSL)

Swift has an official Windows toolchain (<https://www.swift.org/install/windows/>,
installable via `winget install Swift.Toolchain`; needs Visual Studio Build Tools
for the Windows SDK). The `CoreLogic` package builds and tests with it, and the
VS Code Swift extension works. It's a fine alternative to Path A if you'd rather
avoid WSL — but Path B (xtool) is documented for Linux/WSL, so WSL is the more
capable home base. Pick one to avoid maintaining two toolchains.

---

## 8. Recommended workflow for GymLog, concretely

**Daily (Windows only):**
1. VS Code → WSL → edit `CoreLogic` + `iOSApp` sources.
2. `swift test` on every parser change; add a corpus case for every mis-parse.
3. `xtool dev` to push the app to your iPhone; test voice logging in the gym.
4. Commit/push.

**Weekly / milestone:** CI (Path D) runs the corpus on every push; on `main`
it produces an archive so breakage on real Apple toolchains is caught early.

**Month 3 (TestFlight alpha) and beyond:** rent or buy the Mac (Path C), create
the Xcode project once, wire fastlane + TestFlight. All day-to-day editing stays
in VS Code on Windows.

**Month 6 (launch):** App Store submission from the Mac.

---

## 9. Troubleshooting quick hits

- **`wsl --install` hangs / virtualization error** → enable Virtualization in
  BIOS and "Virtual Machine Platform" in Windows Features.
- **usbipd attach works but `idevice_id -l` is empty** → `sudo systemctl start
  usbmuxd` (or run `sudo usbmuxd` once), re-plug, tap **Trust** on the iPhone.
- **`swift test` explodes with missing libcurl/libxml2** → re-run the `apt install`
  line in §2.2.
- **App vanishes from the iPhone after a week** → that's the free-account 7-day
  certificate; re-run `xtool dev` (or pay the $99 to make it annual).
- **SourceKit autocomplete dead in VS Code** → `Ctrl+Shift+P` → "Swift: Restart
  LSP Server", and make sure you opened the folder *via WSL*, not `\\wsl$` paths
  from a Windows-side window.
- **Slow builds** → keep the repo in the WSL filesystem (`~/gymlog`), not `/mnt/c`.

---

## 10. Cost summary

| Item | When | Cost |
|---|---|---|
| WSL2, Swift, VS Code, extensions, xtool | Now | $0 |
| Apple ID (7-day signing) | Now | $0 |
| Apple Developer Program | Month 3–4 (TestFlight) | $99/yr |
| Used M1 Mac mini **or** cloud Mac | Month 3–6 | ~$300 one-time / ~$25+ per mo |
| GitHub Actions | Optional | $0 (free tier) |
