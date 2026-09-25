# Forensic Analysis: Headless Browser Profile Leaks & Transient Package Garbage Collection

**Subject:** Automated Testing Artifact Leakage & Ephemeral Storage Reclamation  
**Impact:** Unchecked degradation of SSD free storage (reclaimed **3.04 GB** of transient bloat)  
**Target Subsystems:** Chromium Headless Runtimes (Puppeteer/Playwright), Docker Desktop Update Pipelines, Node.js Package Managers (`npm`, `pnpm`)

---

## 1. Executive Summary

In continuous integration and local test-driven development (TDD), automated integration tests frequently instantiate headless Chromium instances to execute End-to-End (E2E) UI validation, DOM assertions, and geospatial rendering tests (e.g., testing MapLibre GL in GIS applications). 

A forensic audit of `%LOCALAPPDATA%\Temp` revealed **66 orphaned profile directories** matching `puppeteer_dev_chrome_profile-*` consuming **1.15 GB** of SSD storage. Concurrently, Docker Desktop's background update service deposited **598.9 MB** of unattended MSI installer files in Temp, while local package caches (`npm-cache`, `pnpm-cache`) accumulated another **1.05 GB**.

Because Windows does not automatically clean `%LOCALAPPDATA%\Temp` directories holding active locks or recent timestamps, and default maintenance scripts only scrub user-level subfolders, these transient artifacts accumulated silently. This document details the forensic discovery, leakage mechanics, and the upgraded Garbage Collection (GC) architecture implemented in `optimize.ps1` v2.0.

---

## 2. Leakage Anatomy & Failure Mechanics

```
┌─────────────────────────────────────────────────────────────┐
│                 DEVELOPER TEST RUNNER (Node.js)             │
│   e.g., `pnpm test` / `pytest` / Puppeteer E2E Script       │
│                            │                                │
│        1. Inits Browser: `puppeteer.launch({...})`          │
│                            ▼                                │
├─────────────────────────────────────────────────────────────┤
│                    CHROMIUM INSTANTIATION                   │
│   Creates Unique Isolated Directory:                        │
│   `%TEMP%\puppeteer_dev_chrome_profile-XXXXXX\`             │
│   • Local State & Default Profile (~45 MB per instance)     │
│   • GPU Shader Cache & IndexedDB                            │
├─────────────────────────────────────────────────────────────┤
│                 THE UNHANDLED TEARDOWN TRAP                 │
│   Scenario A: Test assertion fails / throws unhandled error │
│   Scenario B: Developer hits `Ctrl+C` in terminal           │
│   Scenario C: Process killed via timeout / memory limit     │
│                            │                                │
│   [RESULT: `browser.close()` NEVER GETS CALLED!]            │
│   Directory persists on SSD FOREVER as an orphaned clone!   │
└─────────────────────────────────────────────────────────────┘
```

### Forensic Inventory:
Querying `%LOCALAPPDATA%\Temp` for test artifacts:
```powershell
Get-ChildItem $env:TEMP -Directory -Filter "puppeteer_dev_chrome_profile-*" | Measure-Object
```
* **Folder Count:** 66 unique directory structures.
* **Storage Footprint:** 1,149.8 MB (~1.15 GB).
* **Average Directory Size:** ~45 MB per test run (comprising default profile databases, font tables, and LevelDB journal files).

---

## 3. Secondary Transient Consumers

Alongside test profiles, forensic disk analysis identified two additional high-growth temporary storage sinks:

1. **Docker Desktop Update Artifacts (`DockerDesktopUpdates`):**
   * Path: `%TEMP%\DockerDesktopUpdates`
   * Footprint: **598.9 MB**
   * Cause: Docker Desktop periodically polls upstream release endpoints and downloads full installer packages in the background. If the user does not immediately click "Update and Restart", the multi-hundred-megabyte MSI payload remains resident indefinitely.
2. **Local Package Manager Stores (`npm-cache` & `pnpm-cache`):**
   * Path: `%LOCALAPPDATA%\npm-cache` (657 MB) + `%LOCALAPPDATA%\pnpm-cache` (402 MB)
   * Footprint: **1,059.4 MB (~1.06 GB)**
   * Cause: Modern package managers store tarballs and uncompressed module trees in `%LOCALAPPDATA%` in addition to `%APPDATA%`. Standard clean scripts querying only `$env:APPDATA\npm-cache` miss the largest local repository.

---

## 4. The v2.0 Garbage Collection (GC) Engine

To permanently prevent recurring storage exhaustion, [scripts/optimize.ps1](../scripts/optimize.ps1) was upgraded from standard single-directory cleaning to a multi-pattern garbage collection engine:

```powershell
# 1. Targeted Automated Test Artifact Purge
Write-Info "Cleaning User Temp & test artifacts..."
$before = Get-FolderSize $env:TEMP

# Pattern-match and recursively remove all Puppeteer isolated profiles
Get-ChildItem $env:TEMP -Directory -Filter "puppeteer_dev_chrome_profile-*" -ErrorAction SilentlyContinue | 
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

# Purge unattended Docker installer payloads
$dockUp = Join-Path $env:TEMP "DockerDesktopUpdates"
if (Test-Path $dockUp) { Remove-Item $dockUp -Recurse -Force -ErrorAction SilentlyContinue }

# Purge Claude VM temporary runtimes
$claudeT = Join-Path $env:TEMP "claude"
if (Test-Path $claudeT) { Remove-Item $claudeT -Recurse -Force -ErrorAction SilentlyContinue }

# 2. Package Manager Store Scrubber (npm, pnpm, pip)
$pkgCaches = @(
    "$env:APPDATA\npm-cache",
    "$env:LOCALAPPDATA\npm-cache",
    "$env:LOCALAPPDATA\pnpm-cache"
)
foreach ($pc in $pkgCaches) {
    if (Test-Path $pc) { Remove-Item $pc -Recurse -Force -ErrorAction SilentlyContinue }
}
try { & pip cache purge 2>$null | Out-Null } catch {}
```

---

## 5. Engineering Best Practices for Test Authors

When writing Puppeteer / Playwright test suites in Node.js or Python, enforce deterministic teardown handlers to prevent profile leakage:

```javascript
// Puppeteer Node.js Best Practice Pattern:
import puppeteer from 'puppeteer';
import fs from 'fs';

let browser;
let userDataDir;

beforeAll(async () => {
    userDataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'test-runner-'));
    browser = await puppeteer.launch({ userDataDir });
});

afterAll(async () => {
    if (browser) {
        await browser.close();
    }
    // Explicitly delete the temporary directory
    if (userDataDir && fs.existsSync(userDataDir)) {
        fs.rmSync(userDataDir, { recursive: true, force: true });
    }
});
```
