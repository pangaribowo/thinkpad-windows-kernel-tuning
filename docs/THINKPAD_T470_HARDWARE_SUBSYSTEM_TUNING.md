# Engineering Guide: Lenovo ThinkPad T470 Hardware & Subsystem Optimization

**Target Workstation:** Lenovo ThinkPad T470 (`20JNS1B300` / `ThinkPad T470 W10DG`), Serial: `PF0W2BGM`  
**CPU Architecture:** Intel Core i5-6300U @ 2.40GHz (2 Cores / 4 Threads, Skylake-U, 15W TDP)  
**Memory Hierarchy:** 8.00 GB DDR4-2133 Single-Channel (Ramaxel `RMSA3260MB78HAF2400`, Slot 2 Empty)  
**Mass Storage:** 128 GB SanDisk SD8SN8U-128G-1006 SATA III SSD (6Gbps, Wear: 0%)  
**Battery Subsystem:** Lenovo Power Bridge Architecture, Rear 24Wh SANYO Pack (`01AV425`, 558 Cycles)  
**OS Environment:** Windows 10 Pro 64-bit 22H2, Build 19045.6466  

---

## 1. Executive Summary

As Windows 10 reaches legacy support milestones, maximizing the longevity, stability, and responsiveness of enterprise hardware requires tuning beyond generic registry scripts. The Lenovo ThinkPad T470 possesses distinctive architectural features—such as the Power Bridge dual-battery subsystem, Intel Skylake Speed Shift hardware P-states, Intel Dual Band Wireless-AC 8260 with dual-antenna MIMO, and an unpopulated second DDR4 SODIMM slot.

This guide details the multi-layer forensic audit and systematic optimization applied across operating system servicing, Wi-Fi physical layers, background CPU contention, memory compression, and BIOS WMI configurations.

---

## 2. Multi-Layer Subsystem Optimization

### 2.1 Memory Compression & SysMain Interaction
On an 8 GB RAM system where memory commit charges routinely peak at 9+ GB during development workloads, disabling `SysMain` (SuperFetch) inadvertently disables Windows 10's in-RAM **Memory Compression** (`MemoryCompression: False`). Consequently, when physical RAM drops below 1 GB, uncompressed dirty pages are evicted straight to the SATA SSD pagefile, causing severe disk thrashing.

```
┌─────────────────────────────────────────────────────────────┐
│                 DIRTY APPLICATION PAGES IN RAM              │
│                               │                             │
│                  Memory Pressure (>85% RAM)                 │
│                               ▼                             │
├─────────────────────────────────────────────────────────────┤
│         WINDOWS MEMORY MANAGER & COMPRESSION STORE          │
│   Compresses dirty pages in-place using WKDM / LZ4 (2.5:1)  │
│                               │                             │
│       Compressed block stored in RAM "Compressed Store"     │
│   (Consumes ~450MB RAM instead of 1.2GB SSD Pagefile I/O!)  │
└─────────────────────────────────────────────────────────────┘
```

**Remediation:**
```powershell
Set-Service -Name "SysMain" -StartupType Automatic
Start-Service -Name "SysMain"
Enable-MMAgent -MemoryCompression -ApplicationPreLaunch
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name "DisablePagingExecutive" -Value 0 -Type DWord
```
*Note: Setting `DisablePagingExecutive = 0` avoids locking ~350 MB of unpageable kernel memory in physical RAM, giving user applications maximum memory headroom.*

---

### 2.2 Windows Defender CPU Contention Mitigation
On a 2-core / 4-thread Skylake processor, the Windows Defender antimalware engine (`MsMpEng.exe`) frequently monopolizes CPU resources (logging over **1,341 CPU seconds**), intercepting file writes across `node_modules`, Python virtualenvs, and Git operations.

**Remediation:**
```powershell
# Developer process exclusions
Add-MpPreference -ExclusionProcess @("node.exe", "npm.cmd", "pnpm.cmd", "python.exe", "git.exe", "code.exe")

# Developer workspace path exclusions
Add-MpPreference -ExclusionPath @(
    "C:\Users\Administrator\Documents\Projects",
    "C:\Users\Administrator\.gemini",
    "C:\nvm4w",
    "$env:LOCALAPPDATA\Programs\Python",
    "$env:LOCALAPPDATA\Programs\Microsoft VS Code",
    "$env:LOCALAPPDATA\pnpm",
    "$env:APPDATA\npm"
)

# Throttle background scan CPU utilization to 20% (down from 50%)
Set-MpPreference -ScanAvgCPULoadFactor 20
```

---

### 2.3 Intel Wi-Fi 8260 Beacon Drops & Antenna Chain Tuning
Forensic inspection of the System Event Log revealed over 1,000 `Netwtw06: 6000 - BSS missed beacons` events on 2.4 GHz Wi-Fi.

**Root Cause:**
1. `Roaming Aggressiveness` was set to `3. Medium`. At 47% signal strength, the driver performed aggressive off-channel background scans to discover alternate BSSIDs, dropping frames on the active link.
2. `MIMO Power Save Mode` was configured to `Auto SMPS` (Spatial Multiplexing Power Save), turning off the secondary physical antenna during low activity.

**Remediation:**
```powershell
Set-NetAdapterAdvancedProperty -Name "Wi-Fi 2" -DisplayName "Roaming Aggressiveness" -DisplayValue "1. Lowest"
Set-NetAdapterAdvancedProperty -Name "Wi-Fi 2" -DisplayName "MIMO Power Save Mode" -DisplayValue "No SMPS"
Set-NetAdapterAdvancedProperty -Name "Wi-Fi 2" -DisplayName "Throughput Booster" -DisplayValue "Enabled"
Set-NetAdapterAdvancedProperty -Name "Wi-Fi 2" -DisplayName "Preferred Band" -DisplayValue "3. Prefer 5GHz band"
```

---

### 2.4 ThinkPad Sleep Battery Drain (`EasyResume`) & CPU Speed Shift
* **Eliminating Sleep Drain:** `Lenovo Instant On` (`EasyResume.exe`) prevents the machine from entering ACPI S3 deep sleep for 30 minutes after lid closure. Disabling this service restores instant sleep and eliminates warm-in-bag battery loss.
* **Speed Shift Idle Clock on AC:** `PROCTHROTTLEMIN` was pinned to 100% on AC, holding the CPU clock at 2.40 GHz constantly. Allowing it to drop to 5% enables the Skylake processor to utilize 800 MHz idle C-states, lowering temperatures and fan noise.

```powershell
Stop-Service -Name "Lenovo Instant On" -Force -ErrorAction SilentlyContinue
Set-Service -Name "Lenovo Instant On" -StartupType Disabled

# Scale idle clock down to 5% on AC
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 5

# Set Balanced EPP (50) on DC to conserve battery, Max Performance (0) on AC
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 36687f9e-e3a5-4dbf-b1dc-15eb381c6863 50
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 36687f9e-e3a5-4dbf-b1dc-15eb381c6863 0
powercfg /setactive SCHEME_CURRENT
```

---

### 2.5 BIOS WMI Tuning: Disabling WiGig Bus Polling
The ThinkPad T470 BIOS includes a setting for Intel WiGig (802.11ad 60GHz wireless docking). However, the installed wireless card is the standard Intel Dual Band Wireless-AC 8260 (not the 18260 WiGig card). Disabling this unused radio prevents pointless PCI-e polling:

```powershell
$wmi = Get-CimInstance -Namespace root\wmi -ClassName Lenovo_SetBiosSetting
$wmi | Invoke-CimMethod -MethodName SetBiosSetting -Arguments @{parameter="WiGig,Disable"}
$save = Get-CimInstance -Namespace root\wmi -ClassName Lenovo_SaveBiosSettings
$save | Invoke-CimMethod -MethodName SaveBiosSettings -Arguments @{parameter=""}
```

---

## 3. Hardware Upgrade Blueprint (Physical Recommendations)

### 1. Dual-Channel DDR4 RAM Upgrade (Highest ROI)
* **Current State:** 1x 8GB DDR4-2133 (`ChannelA-DIMM0`). **Slot 2 is empty**.
* **Upgrade:** Install a second 8GB DDR4 SODIMM stick (DDR4-2400 / 2666 / 3200; will downclock to 2133MHz matching JEDEC specs) for approximately $15–$20.
* **Impact:**
  - Doubles system memory to **16 GB**, permanently eliminating memory pressure.
  - Activates **Dual-Channel 128-bit memory bus**, doubling theoretical memory bandwidth from ~17 GB/s to ~34 GB/s.
  - Delivers a **+30% to +50% FPS boost to the Intel HD Graphics 520 GPU** (which shares system memory), resulting in fluid video playback and snappy UI rendering.

### 2. Front Internal 24Wh Battery Installation
* **Current State:** Only the rear 24Wh 3-cell battery pack (`01AV425`) is installed.
* **Upgrade:** Install the front internal 24Wh battery (Lenovo Part Numbers: `01AV405`, `01AV406`, or `01AV407`).
* **Impact:**
  - Doubles total battery capacity from 24Wh to **48Wh**.
  - Restores full ThinkPad Power Bridge hot-swapping functionality.
  - Increases real-world mobile battery life to **8–10 hours**.
