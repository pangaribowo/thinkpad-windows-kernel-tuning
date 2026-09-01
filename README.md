# Windows Performance Engineering & Kernel Subsystem Tuning
### *Low-Resource Workstation Optimization Case Study: Intel i5-6300U / 8GB RAM / 128GB SSD*

[![Platform](https://img.shields.io/badge/Platform-Windows%2010%20%7C%2011%20(64--bit)-0078D6?logo=windows)](https://microsoft.com/windows)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-5391FE?logo=powershell)](https://github.com/PowerShell/PowerShell)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Architecture](https://img.shields.io/badge/Architecture-Kernel%20%7C%20TCP%20%7C%20Chromium%20%7C%20WSL2-orange)]()

---

## 📌 Executive Summary

Modern software development workflows (running IDEs, Chromium-based browsers, Docker containers, Language Server Protocols, and Git toolchains) are notoriously resource-intensive. When deployed on constrained hardware—such as an enterprise ultrabook with **2 physical cores (4 threads), 8 GB RAM, and a 128 GB SSD**—standard Windows defaults frequently result in severe resource starvation:

* **Storage Exhaustion:** Cumulative browser profiles, container images, crash dumps, and unbounded virtual memory (`pagefile.sys`) push SSD capacity to critical thresholds (>98% utilization).
* **Memory Saturation:** Unmanaged multi-process architectures (Chromium renderer sandboxes, WSL2 dynamic memory inflation) trigger aggressive page swapping and system thrashing.
* **CPU Scheduling Inefficiencies:** Windows default thread quantum allocation (`Win32PrioritySeparation = 2`) and background telemetry interrupt active foreground development workflows.

This repository provides an **engineering-grade case study, architectural analysis, and automated toolchain** that systematically diagnoses and optimizes Windows at the **Kernel, Subsystem, File System, Network Stack, and Application layers**.

---

## 📊 Benchmark & Key Performance Indicators (KPIs)

Empirical results measured on a **Lenovo ThinkPad (Intel Core i5-6300U @ 2.40GHz, 8GB DDR4, SanDisk 128GB SSD)**:

| Metric / Parameter | Pre-Optimization Baseline | Post-Optimization State | Net Improvement |
| :--- | :---: | :---: | :---: |
| **SSD Free Storage (C:)** | **1.05 GB** *(Critical / 99% Full)* | **27.23 GB** *(Healthy / 23% Free)* | **+26.18 GB (+2,493%)** |
| **Idle CPU Load** | **~67%** *(Telemetry/Polling spikes)* | **~19%** *(Clean & Idle)* | **-71.6% Background Overhead** |
| **Virtual Memory (Pagefile)** | **14.03 GB** *(Dynamic unbounded)* | **4.00 GB - 8.00 GB** *(Bounded)* | **~6.00 GB Storage Reclaimed** |
| **WSL2 / Docker RAM Allocation** | **50% Host RAM (Up to 4.0 GB)** | **2.50 GB Cap + Page Reporting** | **Zero Host RAM Starvation** |
| **Chromium (Brave) Tab Management** | *Active unbounded in RAM* | *Automatic Tab Discarding & GPU Offload* | **~40% - 60% Idle Tab RAM Saved** |
| **Git Operations (`status`, `diff`)** | *Single-threaded POSIX stat() calls* | *`fscache` + `preloadindex` active* | **5x - 10x Throughput Acceleration** |
| **SSD Physical Block Health** | *Dirty NAND Flash pages* | *Manual ReTrim (30.49 GB trimmed)* | **Restored NAND Write Latency** |

---

## 🏗️ Multi-Layer Optimization Architecture

```
┌────────────────────────────────────────────────────────────────────────┐
│                        USER & APPLICATION LAYER                        │
│  • Domain-Driven Directory Restructuring (PARA / Domain Framework)     │
│  • Chromium Enterprise Policies (HighEfficiencyMode, GPU Offloading)   │
│  • Multi-Threaded Git Engine (core.fscache, core.preloadindex)         │
├────────────────────────────────────────────────────────────────────────┤
│                       SYSTEM SERVICES & TELEMETRY                      │
│  • Diagnostic Data & Telemetry Daemon (DiagTrack) Termination          │
│  • Unnecessary UWP Bloatware Removal (15 Provisioned Packages)         │
│  • Delivery Optimization P2P Seeding Disabled                          │
├────────────────────────────────────────────────────────────────────────┤
│                     VIRTUALIZATION & CONTAINER LAYER                   │
│  • WSL2 Linux Kernel Memory Capping (.wslconfig: memory=2560MB)        │
│  • Dynamic Page Reporting & Memory Reclaim Automation                  │
├────────────────────────────────────────────────────────────────────────┤
│                      KERNEL & SCHEDULING SUBSYSTEM                     │
│  • CPU Thread Quantum Tuning (Win32PrioritySeparation = 0x1A / 26)     │
│  • SystemResponsiveness = 0 (100% CPU priority for foreground tasks)   │
│  • NetworkThrottlingIndex Disabled (Unrestricted TCP throughput)       │
├────────────────────────────────────────────────────────────────────────┤
│                   STORAGE & NETWORK PROTOCOL SUBSYSTEM                 │
│  • TCP Congestion Control Provider: Compound TCP (CTCP) + RACK         │
│  • NTFS LastAccess Timestamping Disabled (Zero read write-IOPS)        │
│  • Physical SSD NAND Flash ReTrim (Trimmed 12,183 allocations)         │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 📂 Repository Structure

```
.
├── README.md                  # Project overview, KPIs, and quickstart guide
├── CASE_STUDY.md              # In-depth technical engineering case study & methodology
├── ARCHITECTURE.md            # Deep-dive into Windows internals, memory paging, and TCP stack
├── LICENSE                    # MIT License
├── scripts/
│   ├── optimize.ps1           # Comprehensive CLI tool (Status, Clean, Tune modes)
│   ├── setup-kernel.ps1       # Kernel scheduler, priority separation & responsiveness tuning
│   ├── setup-wsl.ps1          # WSL2/Docker memory ceiling & page reporting setup
│   ├── setup-git.ps1          # Git multi-threaded caching & filesystem optimization
│   └── setup-brave.ps1        # Chromium / Brave enterprise memory saver policy deployment
└── launchers/
    ├── System-Status.bat      # 1-Click interactive system diagnostics terminal
    └── Optimize-Clean.bat     # 1-Click routine cache & temporary data scrubber
```

---

## 🚀 Quickstart

### Prerequisites
* Windows 10 (Build 19041+) or Windows 11 (64-bit).
* Administrator privileges (required for Kernel registry and TCP/IP stack modifications).
* PowerShell 5.1 or PowerShell 7+.

### 1. Clone the Repository
```bash
git clone https://github.com/pangaribowo/thinkpad-windows-kernel-tuning.git
cd thinkpad-windows-kernel-tuning
```

### 2. Check System Health & Diagnostics
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\optimize.ps1 -Mode Status
```

### 3. Run Routine Cache Cleanup
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\optimize.ps1 -Mode Clean
```

### 4. Apply Subsystem & Kernel Tuning (One-Time Execution)
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\optimize.ps1 -Mode Tune
```

---

## 📖 Deep Technical Documentation

For in-depth analysis of the engineering principles applied in this project, explore:

* 📄 **[CASE_STUDY.md](CASE_STUDY.md)** — Step-by-step breakdown of the incident response, cloud triage, bloatware forensics, and recovery methodology.
* 🧠 **[ARCHITECTURE.md](ARCHITECTURE.md)** — Technical deep-dive into Windows NT Quantum Scheduling, Compound TCP dynamics, WSL2 memory hypervisor management, and NTFS caching mechanics.

---

## 👤 Author & Contributor

**Fatahillah Alif Pangaribowo**
* GitHub: [@pangaribowo](https://github.com/pangaribowo)
* Email: [fatahillahalifp04@gmail.com](mailto:fatahillahalifp04@gmail.com)
* Focus: Cyber Security, Kernel & Systems Engineering, Cloud Infrastructure

---

## 📜 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
