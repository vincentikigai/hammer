# hammer

A collection of networking and productivity utilities for Windows and Raspberry Pi.

## Tools

### 🕒 [active-time-tracker](./active-time-tracker/)
Automatically monitors user activity and logs work sessions with zero manual effort. Features a cross-platform Go client that syncs multiple devices (Windows, macOS, Linux) into a unified Markdown report via Cloud Sync.

**Highlights:** Multi-device sync · Smart idle detection · JSON + CSV + Markdown reports · Midnight session splitting · Run at login

---

### 🌐 [internet-accesibility](./internet-accesibility/)
Monitors internet and VPN connectivity in real time. Distinguishes between a total internet outage and a global-only reachability issue by checking both `google.com` and `baidu.com`.

**Highlights:** Color-coded status (🟢🟡🔴) · Windows toast notifications · Background execution · PowerShell

---

### 🔀 [ip-switcher](./ip-switcher/)
Interactive scripts to switch your network adapter's IP configuration between DHCP and static profiles.

**Highlights:** Cross-platform (Windows PowerShell + Linux Bash) · Interactive profile menu · Configurable static IP profiles

---

### 📡 [ip-tracker](./ip-tracker/)
Monitors and logs changes to your external IP address and DNS servers. Tracks connection sessions, latency, and the country associated with your IP.

**Highlights:** Change detection · Session duration logging · Country lookup via ip-api · CSV export · Test/dummy mode

---

### 🚀 [speed-monitor](./speed-monitor/)
Continuously monitors internet speed at configurable intervals with color-coded status indicators and threshold warnings.

**Highlights:** Real-time download/upload/ping · Threshold alerts (🟢🟡🔴) · Daily log files · Configurable intervals · PowerShell

---

### ⚡ [speed-tester](./speed-tester/)
A Python-based internet speed testing tool designed for scheduled, unattended runs on a Raspberry Pi. Logs all results to a CSV file.

**Highlights:** Ping / download / upload logging · Auto-retry if below speed threshold · Logs every attempt · Scheduled via `cron`
