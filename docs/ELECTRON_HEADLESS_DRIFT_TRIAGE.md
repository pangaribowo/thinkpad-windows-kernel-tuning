# Incident Post-Mortem: Electron Multi-Monitor Viewport Drift & Zombie Process Retention

**Incident Reference:** INC-20260915-APP-02  
**Severity:** Moderate (Application Inoperable / Blank White Screen)  
**System Impact:** Claude Desktop failed to display interactive GUI; consumed 1.2 GB of RAM across 15 background zombie processes  
**Subsystem:** Electron Framework, Chromium Content Module, Desktop Window Manager (DWM), Direct3D/WebGL

---

## 1. Executive Summary

During daily operations, Claude Desktop for Windows exhibited a persistent, non-responsive blank white screen upon launch. Task Manager and PowerShell process queries revealed that **15 orphan `claude.exe` background processes** had accumulated in memory over multiple days without terminating. 

Forensic parsing of the application's configuration state file (`window-state.json`) revealed that the main browser window coordinates had drifted off-screen to horizontal pixel position `x: 1093` with width `1200`, exceeding the native display boundary of the laptop (1366x768). The Electron rendering engine attempted to initialize a hardware-accelerated WebGL viewport in a non-existent display rect, resulting in an unrecoverable rendering stall.

Remediation required terminating all zombie process trees, programmatically resetting the viewport coordinate state to within primary monitor bounds, and purging stale GPU shader caches.

---

## 2. Multi-Process Electron Architecture Breakdown

Modern desktop applications built on Electron (such as Claude Desktop, VS Code, Discord, and Slack) operate under a multi-process Chromium architecture:

```
┌──────────────────────────────────────────────────────────────┐
│                    BROWSER (MAIN) PROCESS                    │
│  • Manages application lifecycle, IPC, and native windows    │
│  • Reads/Writes window-state.json on startup & shutdown      │
├───────────────┬──────────────────────────────┬───────────────┤
│               │                              │               │
▼               ▼                              ▼               ▼
[RENDERER 1]    [RENDERER 2]             [GPU PROCESS]    [UTILITY / VM]
WebContents     Off-screen Viewport      Direct3D 11      claude-code-vm
Sandboxed DOM   (Stalled at x:1093)      ANGLE / WebGL    rootfs.vhdx
```

### The Two Interconnected Failure Modes:

### Failure Mode 1: The Multi-Monitor Coordinate Drift Trap
When a laptop is connected to an external secondary monitor (e.g., dual-display 1080p setup):
1. The user drags the application window to the secondary display (e.g., placed at `x: 1093, y: 420`).
2. Upon closing or suspending the laptop, Electron serializes the current window geometry into:
   `%LOCALAPPDATA%\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\Claude\window-state.json`
3. When the laptop subsequently disconnects from the external monitor and boots into standalone mobile mode (single built-in display: **1366x768**):
   * Electron reads `window-state.json` without verifying if the target display device currently exists in the Windows EnumDisplayMonitors API.
   * The window rectangle `(x: 1093, width: 1200)` spans from pixel 1093 to 2293. Over 70% of the window is off-screen.
   * The DWM compositor and Chromium GPU process fail to map backbuffer swapchains for viewports intersecting invalid monitor bounds, stalling the DOM render loop and displaying a permanent white frame.

### Failure Mode 2: Zombie Process Accumulation
When Electron applications encounter unhandled GPU swapchain failures or suspend during sleep states:
* Renderer processes and Node.js utility workers fail to receive the `SIGTERM` / `WM_CLOSE` signal dispatched by the Main process.
* Over 48 hours of sleep/wake cycles, **15 zombie instances of `claude.exe`** remained resident, holding file locks on cache databases and consuming **1.2 GB of physical RAM**.

---

## 3. Forensic Evidence

### Viewport Coordinate Inspection:
Querying `window-state.json`:
```json
{
  "x": 1093,
  "y": 420,
  "width": 1200,
  "height": 680,
  "isMaximized": false,
  "isFullScreen": false
}
```
*Calculated right boundary: $1093 + 1200 = 2293\text{ px}$. Physical screen limit: $1366\text{ px}$. Out of bounds by $+927\text{ px}$.*

### Process Tree Inspection:
```powershell
Get-Process -Name "claude" | Select-Object Id, WorkingSet64, StartTime | Format-Table -AutoSize
```
*Identified 15 concurrent instances with start timestamps spanning multiple days.*

---

## 4. Remediation & Recovery Runbook

### Step 1: Forcefully Terminate Zombie Process Trees
```powershell
taskkill /F /IM claude.exe /T
```

### Step 2: Sanitize Viewport Coordinates
Write centered coordinates guaranteed to fit within standard display resolutions ($\ge 1280\times 720$):
```powershell
$statePath = "$env:LOCALAPPDATA\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\Claude\window-state.json"
$safeState = @{
    x = 80
    y = 40
    width = 1200
    height = 680
    isMaximized = $false
    isFullScreen = $false
} | ConvertTo-Json
Set-Content -Path $statePath -Value $safeState -Encoding UTF8
```

### Step 3: Clear Stale GPU Shader Caches
Purge corrupted Direct3D and ANGLE shader caches:
```powershell
$claudeData = "$env:LOCALAPPDATA\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\Claude"
$caches = @("GPUCache", "DawnGraphiteCache", "DawnWebGPUCache", "Code Cache")
foreach ($c in $caches) {
    $target = Join-Path $claudeData $c
    if (Test-Path $target) { Remove-Item "$target\*" -Recurse -Force -ErrorAction SilentlyContinue }
}
```

### Step 4: Relaunch Application via UWP Execution Alias
```powershell
Start-Process "shell:AppsFolder\Claude_pzs8sxrjxfjjc!Claude"
```
*Claude Desktop launched cleanly with interactive UI and full hardware acceleration restored.*

---

## 5. Architectural Recommendations for Electron Developers

1. **Display Bounds Validation:** Always validate deserialized coordinates against `screen.getAllDisplays()` before invoking `BrowserWindow.setBounds()`. If coordinates lie outside all active display viewports, fallback to `{ center: true }`.
2. **Strict Teardown Handlers:** Bind `app.on('before-quit')` to explicitly terminate child utility and worker process trees via process groups.
