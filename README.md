# Windows Performance Engineering & Kernel Subsystem Tuning (v2.0)
### *Production-Grade Workstation Optimization & Forensics Case Study: Intel i5-6300U / 8GB RAM / 128GB SSD*

[![Platform](https://img.shields.io/badge/Platform-Windows%2010%20%7C%2011%20(64--bit)-0078D6?logo=windows)](https://microsoft.com/windows)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-5391FE?logo=powershell)](https://github.com/PowerShell/PowerShell)
[![Version](https://img.shields.io/badge/Release-v2.0%20Enterprise-success.svg)]()
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Architecture](https://img.shields.io/badge/Architecture-Kernel%20%7C%20NDIS%20%7C%20NTFS%20%7C%20WSL2%20%7C%20CompactOS-orange)]()

---

## 📌 Executive Summary & Threat / Problem Model

Modern engineering workflows—spanning container runtimes (Docker/WSL2), multi-threaded compiler chains, language server protocols (LSP), automated browser test suites (Puppeteer/Playwright), and Chromium renderers—impose enterprise-tier hardware requirements. When executed on hardware-constrained developer machines—such as a legacy enterprise ultrabook (**Intel Core i5-6300U @ 2.40GHz, 2 Cores / 4 Threads, 8 GB DDR4, 128 GB SanDisk SSD**)—out-of-the-box Windows NT defaults induce critical operational degradation:

1. **Storage Cascade & Worktree Failures:** Cumulative virtual disk images (`docker_data.vhdx`, Claude VM `rootfs.vhdx`), unmanaged automated test profile dumps (66+ orphaned Puppeteer profiles), and multi-profile browser caches reduce free SSD storage to below **1.5 GB**, triggering hard operational failures in Git worktrees and compiler caches.
2. **Kernel Driver Collisions & Network Stack Crashes:** Third-party hypervisor filter drivers (such as VirtualBox NDIS6 Lightweight Filter `oracle_VBoxNetLwf`) bound to Wi-Fi and WSL virtual adapters corrupt Windows Internet Connection Sharing (ICS), inducing kernel-level `ipnathlp.dll` Access Violations (`0xc0000005`) that kill Mobile Hotspot functionality upon activation.
3. **Memory Starvation & Thread Contention:** Unbounded paging executive mechanics page essential kernel drivers to disk under high memory load, introducing input lag, cursor stuttering, and window transition frame drops on Intel HD Graphics 520.
4. **Desktop Shell Latency:** Default Windows UI delays (`MenuShowDelay = 400ms`, `KeyboardDelay = 1` [~500ms initial hesitance], window minimize/maximize animation curves) introduce perceptual latency across daily engineering tasks.

This repository provides an **architectural analysis, incident response post-mortem, and automated tuning engine** that elevates low-resource ThinkPad hardware to high-responsiveness enterprise workstation standards.

---

## 📊 Empirical Key Performance Indicators (KPIs)

All metrics represent **reproducible, empirically measured production data** captured across live troubleshooting and optimization sessions:

| Metric / Parameter | Pre-Optimization Baseline | Post-Optimization State (v2.0) | Measurable Impact |
| :--- | :---: | :---: | :---: |
| **SSD Free Storage (`C:`)** | **1.63 GB** *(Critical / 98.6% Full)* | **24.01 - 30.49 GB** *(Healthy / 25.6% Free)* | **+28.86 GB Total Recovered (+1,770%)** |
| **Mobile Hotspot / ICS Stability** | **Immediate Crash** *(`ipnathlp.dll` 0xc0000005)* | **100% Operational** *(Verified 1 client active)* | **Zero Kernel Filter Interception** |
| **Keyboard Input Latency** | **~500ms** *(Default KeyboardDelay = 1)* | **~250ms / Instant** *(KeyboardDelay = 0, Speed = 31)* | **Zero Initial Key Hesitance** |
| **Window / Context Menu Latency** | **100ms - 400ms Delay** *(Default animation)* | **0ms Instant Pop-up** *(MenuShowDelay = 0, MinAnimate = 0)* | **Frame Drops Eliminated** |
| **Kernel Driver Memory Residency** | *Paged out to SSD under load* | *Locked in Physical RAM (`DisablePagingExecutive = 1`)* | **Zero Page Fault IOPS on Kernel APIs** |
| **Idle CPU Utilization** | **~67%** *(Telemetry/Polling spikes)* | **~19%** *(Clean & Idle)* | **-71.6% Background CPU Overhead** |
| **Virtual Memory (`pagefile.sys`)** | **14.03 GB** *(Dynamic unbounded)* | **4.00 GB - 8.00 GB** *(Bounded)* | **~6.00 GB Reclaimed Storage** |
| **WSL2 / Docker RAM Allocation** | **50% Host RAM (Up to 4.0 GB)** | **2.50 GB Cap + Page Reporting** | **Zero Host RAM Starvation** |
| **Automated Test Profile Leaks** | **66 Orphaned Folders (~1.15 GB in Temp)** | **Automated Clean via `optimize.ps1` v2.0** | **100% Automated Garbage Collection** |
| **OS Footprint Compression** | *Uncompressed NTFS System Files* | *CompactOS XPRESS/LZX Kernel Compression* | **+2.5 to 4.0 GB Permanent Disk Gain** |

---

## 🏗️ Multi-Layer Workstation Architecture

```
┌────────────────────────────────────────────────────────────────────────┐
│                        USER & APPLICATION LAYER                        │
│  • Upgraded Routine Scrubber: Temp, Puppeteer Profiles, Multi-Brave    │
│  • Chromium Enterprise Policies: HighEfficiencyMode, Tab Discarding   │
│  • Multi-Threaded Git Engine: core.fscache, core.preloadindex          │
├────────────────────────────────────────────────────────────────────────┤
│                      SHELL & INPUT RESPONSIVENESS                      │
│  • Instant Keyboard Repeat: KeyboardDelay = 0, KeyboardSpeed = 31      │
│  • Zero-Delay Shell: MenuShowDelay = 0ms, MinAnimate = 0 (No Lag)      │
│  • Desktop Composition: TaskbarAnimations = 0, DisallowShaking = 1     │
├────────────────────────────────────────────────────────────────────────┤
│                       SYSTEM SERVICES & TELEMETRY                      │
│  • Diagnostic Data & Telemetry (DiagTrack) Terminated                  │
│  • Provisioned UWP Bloatware Scrubbed & WindowsApps Cleaned            │
│  • Delivery Optimization P2P & Background Edge Pre-Launch Disabled     │
├────────────────────────────────────────────────────────────────────────┤
│                     VIRTUALIZATION & CONTAINER LAYER                   │
│  • WSL2 Linux Kernel Memory Capped (.wslconfig: memory=2560MB)         │
│  • Docker Desktop Autostart Management & VHDX Compaction               │
├────────────────────────────────────────────────────────────────────────┤
│                      KERNEL & SCHEDULING SUBSYSTEM                     │
│  • CPU Thread Quantum: Win32PrioritySeparation = 0x1A (3:1 Boost)      │
│  • Multimedia Scheduler: SystemResponsiveness = 0 (100% Foreground)   │
│  • Paging Executive: DisablePagingExecutive = 1 (Kernel in RAM)        │
├────────────────────────────────────────────────────────────────────────┤
│                   STORAGE & NETWORK PROTOCOL SUBSYSTEM                 │
│  • CompactOS: XPRESS/LZX Kernel NTFS System Compression                │
│  • NDIS Unbinding: Decouple oracle_VBoxNetLwf from WSL/Wi-Fi/LAN       │
│  • TCP Stack: Compound TCP (CTCP) + RACK Fast Recovery + No Throttling │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 📂 Repository Structure

```
.
├── README.md                      # Executive Presentation Tier & Benchmark Matrix
├── CASE_STUDY.md                  # Comprehensive Incident Forensics, Triage & Post-Mortem
├── ARCHITECTURE.md                # Deep-dive into Windows Internals, NDIS, CompactOS & Memory
├── LICENSE                        # MIT License
├── docs/                          # Specialized Technical Runbooks & Forensic Post-Mortems
│   ├── NDIS_FILTER_COLLISION_TRIAGE.md     # ICS crash post-mortem & oracle_VBoxNetLwf decoupling
│   ├── START_MENU_INPUT_LATENCY_RUNBOOK.md # Windows Key & SearchApp zero-latency tuning
│   ├── ELECTRON_HEADLESS_DRIFT_TRIAGE.md   # Electron viewport drift & zombie process recovery
│   ├── AUTOMATED_TESTING_LEAK_FORENSICS.md # Puppeteer profile leakage & GC engine architecture
│   └── COMPACTOS_NTFS_COMPRESSION_GUIDE.md # CompactOS XPRESS/LZX kernel transparent compression
├── scripts/
│   ├── optimize.ps1               # Automated Maintenance Engine v2.0 (Status, Clean, Tune)
│   ├── tune-responsiveness.ps1    # Input latency, typing responsiveness & shell animator tuner
│   ├── setup-kernel.ps1           # Kernel scheduler, priority separation & responsiveness
│   ├── setup-wsl.ps1              # WSL2/Docker memory ceiling & page reporting setup
│   ├── setup-git.ps1              # Git multi-threaded caching & filesystem optimization
│   └── setup-brave.ps1            # Chromium / Brave enterprise memory saver deployment
└── launchers/
    ├── System-Status.bat          # 1-Click interactive system diagnostics terminal
    ├── Optimize-Clean.bat         # 1-Click routine cache & temporary data scrubber
    └── Tune-Responsiveness.bat    # 1-Click input latency & UI snappiness applicator
```

---

## 🚀 Quickstart & Reproduction Guide

### Prerequisites
* **Operating System:** Windows 10 (Build 19041+) or Windows 11 (64-bit).
* **Hardware Profile:** Intel Core i3/i5/i7 (Optimized for 2C/4T or 4C/8T with $\le$ 16GB RAM).
* **Permissions:** Administrator privileges (required for Kernel registry, NDIS bindings, and CompactOS).
* **Shell:** PowerShell 5.1 or PowerShell 7+.

### 1. Clone the Repository
```bash
git clone https://github.com/pangaribowo/thinkpad-windows-kernel-tuning.git
cd thinkpad-windows-kernel-tuning
```

### 2. Inspect Live System Diagnostics
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\optimize.ps1 -Mode Status
```

### 3. Run Automated Cache & Test Artifact Scrubbing (v2.0)
Reclaims 2 to 5+ GB of temporary files, Puppeteer test dumps, multi-profile browser caches, and updaters:
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\optimize.ps1 -Mode Clean
```

### 4. Apply High-Tier Responsiveness & Input Latency Tuning
Eliminates keyboard repeat hesitation, window transition lag, and unbinds conflicting network filter drivers:
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\tune-responsiveness.ps1
```

### 5. Enable Kernel CompactOS Compression (One-Time)
Compresses Windows system files using native kernel XPRESS/LZX algorithms:
```powershell
compact /compactos:always
```

---

## 📖 Deep Technical Documentation & Runbooks

### 🏛️ Core Architectural Documents
* 📄 **[CASE_STUDY.md](CASE_STUDY.md)** — Step-by-step incident response, NDIS crash forensics (`ipnathlp.dll`), Puppeteer artifact leakage, and storage recovery methodologies.
* 🧠 **[ARCHITECTURE.md](ARCHITECTURE.md)** — Technical deep-dive into NT Quantum Scheduling, CompactOS compression algorithms, NDIS 6.x Lightweight Filters, and Win32 Raw Input queue dynamics.

### 📚 Specialized Deep-Dive Guides (`docs/`)

| Document | Scope & Technical Engineering Coverage |
| :--- | :--- |
| **[docs/NDIS_FILTER_COLLISION_TRIAGE.md](docs/NDIS_FILTER_COLLISION_TRIAGE.md)** | **ICS Subsystem Access Violation Post-Mortem:** Forensic investigation into `ipnathlp.dll` crash (`0xc0000005`) caused by VirtualBox `oracle_VBoxNetLwf` NDIS6 filter driver, with programmatic decoupling runbook. |
| **[docs/START_MENU_INPUT_LATENCY_RUNBOOK.md](docs/START_MENU_INPUT_LATENCY_RUNBOOK.md)** | **Windows Key & SearchApp Input Latency:** Low-level anatomy of Start Menu delays, Bing Web Search API elimination, Cortana consent decoupling, and sub-30ms local-only search configuration. |
| **[docs/ELECTRON_HEADLESS_DRIFT_TRIAGE.md](docs/ELECTRON_HEADLESS_DRIFT_TRIAGE.md)** | **Electron Multi-Monitor Viewport Drift:** Post-mortem of Claude Desktop white screen hangs, 15 zombie process memory retention, and off-screen window coordinate drift (`window-state.json`). |
| **[docs/AUTOMATED_TESTING_LEAK_FORENSICS.md](docs/AUTOMATED_TESTING_LEAK_FORENSICS.md)** | **Headless Browser Test Profile Forensics:** Audit of 66 leaked Puppeteer profiles (~1.15 GB in Temp), Docker update bloat, and the upgraded multi-pattern GC architecture in `optimize.ps1` v2.0. |
| **[docs/COMPACTOS_NTFS_COMPRESSION_GUIDE.md](docs/COMPACTOS_NTFS_COMPRESSION_GUIDE.md)** | **CompactOS Kernel File Compression:** Mechanics of `wof.sys`, XPRESS/LZX algorithms, and empirical proof of how reading smaller compressed blocks over SATA SSD accelerates system I/O while saving 2.5–4 GB. |

---

## 👤 Author & Contributor

**Fatahillah Alif Pangaribowo**
* GitHub: [@pangaribowo](https://github.com/pangaribowo)
* Email: [fatahillahalifp04@gmail.com](mailto:fatahillahalifp04@gmail.com)
* Focus: Systems Engineering, Kernel Subsystems, Cybersecurity & Cloud Infrastructure

---

## 📜 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
