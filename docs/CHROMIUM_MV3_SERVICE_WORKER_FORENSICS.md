# Forensic Post-Mortem: Chromium Manifest V3 Service Worker Desynchronization & EcoQoS Starvation

**Incident Reference:** INC-20261013-BRW-06  
**Severity:** High (Manifest V3 Browser Extensions Dead on Click Across 18 Profiles)  
**System Impact:** Tab Suspender (`fiabciakcmgepblmdkmemdbbkilneeeh` v2.0.12) and other Manifest V3 extensions failed to respond to toolbar clicks, hotkeys, or background alarms on first browser launch after cache scrubbing  
**Target Subsystems:** Chromium `ServiceWorkerRegistry` (LevelDB `Database` vs SimpleCache `ScriptCache`), Windows NT Power Manager (`EcoQoS` / `BasePriority 4`), Chromium Extension Storage (`IndexedDB` & `Local Extension Settings`)

---

## 1. Executive Summary

Following routine workstation cache maintenance via `Optimize-Clean 2xmg.bat` (`scripts/optimize.ps1 -Mode Clean`), Manifest V3 browser extensions in Brave Browser—most visibly **Tab Suspender v2.0.12** (`fiabciakcmgepblmdkmemdbbkilneeeh`)—stopped responding when clicked across multiple user profiles (`Profile 2`, `Profile 6`, `Profile 9`, `Profile 10`, `Profile 22`, and 13 additional profiles).

Forensic investigation uncovered **three compounding failure mechanisms**:

1. **Primary Root Cause (The Recurrence Trigger) — LevelDB vs SimpleCache Desynchronization:**  
   `scripts/optimize.ps1` previously included `"Service Worker\ScriptCache"` and `"Service Worker\CacheStorage"` inside its `$cacheDirs` purge array while leaving `"Service Worker\Database"` untouched. Because Chromium stores Service Worker registration metadata (`REG:chrome-extension://<id>/`) in `Service Worker\Database` (LevelDB) and stores the corresponding compiled/raw worker script payloads (`worker.js` + 30 `importScripts` modules) in `Service Worker\ScriptCache` (SimpleCache), deleting `ScriptCache` alone broke the invariant between metadata and disk cache. Upon next launch, Chromium encountered `ServiceWorkerStatusCode::kErrorDiskCache`, wrote a LevelDB deletion record (`kTypeDeletion` / `type=0`) for `REG:chrome-extension://fiabciakcmgepblmdkmemdbbkilneeeh/`, and left the extension dead for the entire browser session until a second browser restart triggered `RE_REGISTER_ON_STATE_MISMATCH`.
2. **Secondary Factor — Windows EcoQoS / Efficiency Mode Thread Starvation:**  
   14 `brave.exe` child processes (including extension service worker and background renderer processes) were throttled by Windows Power Throttling / Chromium background priority management to `PriorityClass = Idle` (`BasePriority = 4`), starving background extension event dispatch on the dual-core Intel Core i5-6300U CPU.
3. **Tertiary Factor — Extension Storage Bloat (`IndexedDB` & `Local Extension Settings`):**  
   Tab Suspender's tab-capture screenshot feature (`chrome.tabs.captureVisibleTab`) accumulated hundreds of base64/binary image blobs and over 180,000 LevelDB keys per profile (`Profile 9`: **36.93 MB** IndexedDB across 456 blobs + **17.59 MB** Local Extension Settings; `Profile 2`: **15.79 MB** + **25.50 MB**), amplifying cold-start I/O latency whenever the Service Worker initialized.

---

## 2. Internal Architecture & Failure State Machine

### 2.1 Chromium Service Worker Storage Coupling
In Chromium's `content/browser/service_worker/` subsystem, an installed Manifest V3 extension background worker relies on two tightly coupled on-disk stores under `<Profile>\Service Worker\`:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    <Profile>\Service Worker\                            │
│                                                                         │
│  ┌─────────────────────────────────┐  ┌──────────────────────────────┐  │
│  │       Database\ (LevelDB)       │  │   ScriptCache\ (SimpleCache) │  │
│  │  • CURRENT / MANIFEST-*         │  │  • index / the-real-index    │  │
│  │  • *.ldb (SSTables)             │  │  • <hash>_0 (Script Body)    │  │
│  │  • *.log (Write-Ahead Log)      │  │  • <hash>_1 (V8 Bytecode)    │  │
│  │                                 │  │                              │  │
│  │  Key:                           │  │  Resource IDs referenced by  │  │
│  │  REG:chrome-extension://<32-id> │─►│  ServiceWorkerRegistration   │  │
│  │  Value: Protobuf Registration   │  │  protobuf in LevelDB!        │  │
│  └─────────────────────────────────┘  └──────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2.2 The Two-Session Failure Cycle (`kErrorDiskCache` → `type=0`)
When a cleaning script deletes `Service Worker\ScriptCache\*` while `Service Worker\Database` remains intact (even when Brave is completely closed):

```
[Session 0: Browser Closed — Cleaner Runs]
  • optimize.ps1 deletes `Service Worker\ScriptCache\*`
  • `Service Worker\Database` still holds `REG:chrome-extension://fiabciak...` (type=1, Active)
       │
       ▼
[Session 1: User Launches Brave — EXTENSION IS DEAD]
  1. ExtensionRegistrar checks `Database`: sees existing registration (`type=1`).
     Does NOT re-register `worker.js` because it assumes registration is valid.
  2. User clicks Tab Suspender icon → Browser wakes Service Worker.
  3. `ServiceWorkerScriptLoader` attempts to read `worker.js` resource ID from `ScriptCache`.
  4. `ScriptCache` returns `net::ERR_CACHE_MISS` → `ServiceWorkerStatusCode::kErrorDiskCache`.
  5. Chromium's `ServiceWorkerRegistry` marks the registration as doomed and appends a
     LevelDB WriteBatch deletion record (`type=0` / `kTypeDeletion`) to `Database\000003.log`.
  6. The Service Worker termination is permanent for Session 1. Clicking the icon does nothing.
       │
       ▼
[Session 2: User Closes & Re-opens Brave — Self-Recovery (Until Next Clean)]
  1. ExtensionRegistrar queries `Database`: sees `REG:chrome-extension://fiabciak...` is missing (`type=0`).
  2. Triggers `RE_REGISTER_ON_STATE_MISMATCH`, compiling `worker.js` + 30 `importScripts` into `ScriptCache`.
  3. Extension works again—until the user runs `Optimize-Clean` again!
```

---

## 3. Forensic Evidence Collected from Production Profiles

### 3.1 LevelDB WriteBatch Binary Inspection (`Service Worker\Database`)
In LevelDB's Write-Ahead Log (`.log`), each WriteBatch entry precedes the key string with a 1-byte record type (`0x01` = `kTypeValue`, `0x00` = `kTypeDeletion`) and a varint key length (`0x38` = 56 bytes for `REG:chrome-extension://<32-char-id>/` + separator).

Scanning all 18 Brave profiles (`C:\Users\Administrator\AppData\Local\BraveSoftware\Brave-Browser\User Data`) revealed:
* **Timestamp Desynchronization:** On active broken profiles (`Profile 2`, `Profile 6`, `Profile 9`, `Profile 22`), `Database\CURRENT` had creation timestamps dating back months (`2026-04-25`, `2026-07-23`, `2026-09-15`), whereas `ScriptCache\index` had a creation timestamp of `2026-10-13 08:20:21 AM` / `08:52:17 AM` (the exact moment `Optimize-Clean 2xmg.bat` ran).
* **WriteBatch Deletion Tombstones (`type=0`):**
  * `Profile 2`: `ScriptCache = 4 files`, `Tab Suspender (fiabciakcmgepblmdkmemdbbkilneeeh) = type=0 (DELETED)`, `ActiveExts = 1`, `DeletedExts = 8`.
  * `Profile 22`: `ScriptCache = 10 files`, `Tab Suspender = type=0 (DELETED)`, `ActiveExts = 1`, `DeletedExts = 1`.
  * `Profile 6`: `ScriptCache = 0 files`, `Tab Suspender = type=0 (DELETED)`, `ActiveExts = 0`, `DeletedExts = 2`.
  * `Profile 9`: `ScriptCache = 0 files`, `Tab Suspender = type=0 (DELETED)`, `ActiveExts = 3`, `DeletedExts = 8`.
* **14 Closed Profiles (`Profile 3`, `7`, `10`, `11`, `12`, `13`, `14`, `16`, `17`, `18`, `20`, `21`, `24`, `28`):** Exhibited wiped `ScriptCache` payloads (`0 files`) alongside existing `Database` manifests, waiting to fail on their next launch.

### 3.2 Extension Storage Bloat Audit (`fiabciakcmgepblmdkmemdbbkilneeeh`)
Measuring the on-disk footprint of Tab Suspender across user profiles revealed massive storage accumulation caused by tab preview screenshots (`IndexedDB`) and historical session state (`Local Extension Settings`):

| Profile | `IndexedDB` (`chrome-extension_fiabciak..._0.indexeddb.blob` + `.leveldb`) | `Local Extension Settings\fiabciak...` | Combined Extension Storage |
| :--- | :---: | :---: | :---: |
| **`Profile 9`** | **36.93 MB** *(456 screenshot blobs)* | **17.59 MB** *(>180,000 LevelDB keys)* | **54.52 MB** |
| **`Profile 2`** | **15.79 MB** | **25.50 MB** | **41.29 MB** |
| **`Profile 6`** | **16.76 MB** | **13.73 MB** | **30.49 MB** |
| **`Profile 22`** | **14.30 MB** | **13.22 MB** | **27.52 MB** |
| **`Profile 10`** | **10.32 MB** | **14.88 MB** | **25.20 MB** |

### 3.3 Windows EcoQoS Process Starvation
Inspecting running `brave.exe` processes via `Get-Process brave | Select-Object Id, PriorityClass, BasePriority`:
* **14 `brave.exe` processes** were running with `PriorityClass = Idle` (`BasePriority = 4`).
* On a 2-core / 4-thread CPU (Intel Core i5-6300U), `BasePriority 4` threads are preempted by any `Normal` (`BasePriority 8`) or boosted foreground (`BasePriority 10–15`) thread, delaying MV3 Service Worker cold-boot execution (`worker.js` + 30 `importScripts` files).

---

## 4. Engineering Remediation & Self-Healing Architecture

### 4.1 Permanent Fix in `scripts/optimize.ps1`
1. **Removed `Service Worker\ScriptCache` and `Service Worker\CacheStorage` from `$cacheDirs`** in both the Brave (`# 5`) and Chrome (`# 6`) scrubbing loops:
   ```powershell
   # Note: Do NOT delete "Service Worker\ScriptCache" or "Service Worker\CacheStorage" alone,
   # as doing so desynchronizes Service Worker\Database and breaks Manifest V3 extensions (e.g., Tab Suspender).
   $cacheDirs = @("Cache", "Code Cache", "GPUCache", "DawnGraphiteCache", "DawnWebGPUCache", "GrShaderCache", "ShaderCache")
   ```
2. **Added Atomic Self-Healing for Desynchronized Closed Profiles:**  
   During `Invoke-Clean`, `optimize.ps1` now checks if `Service Worker\Database\CURRENT` exists while `ScriptCache\index` is missing, has `0` payload files, or has a `CreationTime` more than 2 minutes newer than `Database\CURRENT`. If the profile is closed (`Database\LOCK` is not held), it atomically resets `Database`, `ScriptCache`, and `CacheStorage` together so Chromium cleanly re-registers all Service Workers on the very first launch.

### 4.2 Dedicated Forensic & Recovery Tool (`scripts/fix-brave-extensions.ps1`)
Authored `scripts/fix-brave-extensions.ps1` (and 1-click launcher `launchers/Fix-Brave-Extensions.bat`) which:
1. Disables Windows Power Throttling on `brave.exe` (`powercfg /powerthrottling disable /path "...\brave.exe"`).
2. Elevates any running `Idle` (`BasePriority 4`) `brave.exe` processes back to `Normal` (`BasePriority 8`).
3. Parses LevelDB `.ldb` SSTables and `.log` WriteBatches in `<Profile>\Service Worker\Database` across all profiles to detect `type=0` (`kTypeDeletion`) records for `REG:chrome-extension://...`, missing `ScriptCache` payloads, or `CreationTime` desynchronization.
4. Atomically resets `Service Worker\Database`, `ScriptCache`, and `CacheStorage` on all unlocked/closed profiles (**14 profiles fixed automatically**) without touching `Local Extension Settings`, `Sync Extension Settings`, or `IndexedDB`.

### 4.3 Critical Operational Safeguard: `brave://restart` vs Extension Toggle
> ⚠️ **WARNING — DO NOT TOGGLE TAB SUSPENDER OFF IN `brave://extensions`:**  
> Suspended tabs in Tab Suspender are navigated to the extension's internal page:  
> `chrome-extension://fiabciakcmgepblmdkmemdbbkilneeeh/park.html?title=...&url=...`  
> In Chromium, disabling or reloading an extension via the `brave://extensions` toggle **immediately closes every open tab belonging to that extension's `chrome-extension://<id>/` origin**. Across multi-window profiles, toggling the extension off destroys hundreds of suspended tabs!  
> **Safe Recovery Procedure for Open Profiles:** Navigate to **`brave://restart`** in the address bar. Chromium gracefully serializes all open windows and `park.html` tab URLs, releases the LevelDB locks, re-registers the Manifest V3 Service Worker, and restores 100% of tabs intact.
