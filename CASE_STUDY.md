# Technical Case Study: Performance Engineering & System Reclamation

**Subject:** Constrained Workstation Resource Recovery & Subsystem Optimization  
**Target Hardware:** Lenovo ThinkPad T460s / Yoga Class Ultrabook  
* **CPU:** Intel Core i5-6300U @ 2.40GHz (2 Cores, 4 Threads, Skylake Microarchitecture)
* **RAM:** 8.00 GB DDR4 (Single Channel)
* **Storage:** SanDisk SD8SN8U-128G SSD (119.13 GiB usable partition)
* **OS:** Windows 10 Pro 22H2 (Build 19045.5011, 64-bit)

---

## 1. Problem Statement & Baseline Incident

In resource-constrained computing environments, running modern multi-tenant developer workloads introduces compounding system friction. The workstation in this case study exhibited critical performance degradation and storage collapse:

1. **Storage Depletion (Disk Exhaustion):**
   * Usable free space on the OS root partition (`C:\`) dropped to **1.05 GB (< 0.9% free)**.
   * High fragmentation and unmanaged application growth: Cumulative Chromium browser profiles (>17 profiles), abandoned Docker virtual disks (`docker_data.vhdx` @ 6.65 GB), and an unbounded Windows Virtual Memory file (`pagefile.sys` inflated to **14.03 GB**).
2. **Memory Contention & Thrashing:**
   * Total system RAM (7.84 GB available) was persistently >85% saturated even during lightweight multitasking.
   * WSL2 / Docker Engine dynamically expanded without an upper ceiling, starving foreground IDEs and compilers.
3. **Background CPU Jitter & Latency:**
   * Average idle CPU utilization hovered around **67%**, dominated by 17+ scheduled diagnostic tasks, telemetry services (`DiagTrack`), and background indexing loops.

---

## 2. Methodology & Execution Roadmap

A structured, 6-phase engineering framework was developed and deployed:

```
[Phase 1: Forensic Audit] ────────> [Phase 2: Automated Cloud Triage]
           │                                      │
           ▼                                      ▼
[Phase 3: Deep System Debloat] ───> [Phase 4: Domain Restructuring]
           │                                      │
           ▼                                      ▼
[Phase 5: Subsystem Tuning] ──────> [Phase 6: Verification & Tooling]
```

---

## 3. Phase-by-Phase Technical Breakdown

### Phase 1: Forensic Disk & Process Telemetry Audit
Using recursive NTFS directory traversals, process grouping, and CIM/WMI queries, the root causes of resource exhaustion were mapped:
* **Virtual Memory Inflation:** Dynamic pagefile allocation allowed `pagefile.sys` to balloon to 14.03 GB due to repeated OOM triggers during Docker/npm compilation bursts.
* **Orphaned Software Packages & Residues:** Abandoned development tooling (PostgreSQL local server, Wireshark, Npcap drivers, Codex CLI runtimes @ 1.33 GB, Zoom Workplace @ 588 MB, Discord cache @ 124 MB) remained registered in file systems and background services despite lack of active usage.
* **Bloatware Daemons:** 15 pre-provisioned Windows UWP application packages (Xbox Suite, Feedback Hub, Maps, Whiteboard, Phone Link) maintained active background brokers.

### Phase 2: Zero-Data-Loss Automated Cloud Triage
Before modifying or moving a single byte of active code or data, an automated, multi-threaded cloud synchronization pipeline was established using **rclone v1.75.0** targeting a Google Cloud Drive remote (`gdriveT5:`):
* **Backed up:** `Documents/`, `Desktop/`, `Pictures/`, `Videos/`, `Downloads/`, `.ssh/`, `.codeium/`, and `Windsurf/`.
* **Verification:** **8,420 files (~5.61 GB)** synchronized with cryptographic checksum validation.
* **Filter Rules:** Strict exclusion of rebuildable build artifacts (`**/node_modules/**`, `**/.git/**`, `**/.cache/**`) to conserve upstream bandwidth.

### Phase 3: Domain-Driven Workspace Reorganization
A flat, domain-driven directory taxonomy was implemented across `C:\Users\Administrator\Documents\` and `Pictures\`, replacing a chaotic, 47-folder disorganized tree:

```
Documents/
├── 🎓 Akademik/         # Thesis (KUAD Slowloris), Defense PPTs, SKPI, Certifications
├── 💻 Projects/         # Active Git repositories (GMF GSE System, PropertiJogja, Devops)
├── 📝 Catatan/          # Second-brain Markdown vaults, research scratchpads, recovered literature
└── 📦 Arsip/            # Historical frozen projects, forensic evidence files, legacy dumps
```

### Phase 4: OS Telemetry & Bloatware Decoupling
* **15 UWP Provisioned Packages Removed:** Executed via `Remove-AppxPackage` and `Remove-AppxProvisionedPackage -Online` to prevent self-healing reinstallation during OS updates.
* **Third-Party Daemon Scrubber:** Removed Glary Utilities, which ran resident memory optimizers (`GUMemfilesService`) that paradoxically increased memory thrashing by forcing aggressive page evictions.
* **Scheduled Task Pruning:** Disabled 13 unneeded recurring scheduled tasks (Lenovo marketing toast alerts, compatibility appraisers, and browser background updaters).

### Phase 5: Kernel, Subsystem & TCP/IP Optimization
1. **Virtual Memory Hardening:**
   Reconfigured `Win32_PageFileSetting` from dynamic unbounded to a **Fixed 4,096 MB initial / 8,192 MB maximum** pagefile. Post-reboot reclaimed **~6.0 GB** of SSD space while preventing pagefile fragmentation.
2. **Kernel Thread Quantum (`Win32PrioritySeparation = 26 / 0x1A`):**
   Adjusted the Windows NT scheduler to prioritize foreground interactive threads over background worker threads in a 3:1 ratio.
3. **Compound TCP (CTCP) & Network Responsiveness:**
   Replaced legacy NewReno TCP congestion algorithms with **CTCP** and enabled **RACK (Recent ACKs)** loss recovery for low-latency API testing and web navigation.
4. **Brave / Chromium Enterprise Policies:**
   Locked global policy enforcing `HighEfficiencyModeEnabled = 1` (automatic tab discarding) and capped disk cache to 256 MB per profile.
5. **WSL2 / Docker Resource Bounding (`.wslconfig`):**
   Capped Linux micro-VM memory to 2.5 GB, 2 CPU threads, and activated dynamic memory reclamation (`pageReporting=true`).
6. **Physical SSD ReTrim:**
   Triggered `Optimize-Volume -ReTrim`, forcing the SanDisk controller to garbage-collect **30.49 GB across 12,183 allocations** of stale NAND blocks.

---

## 4. Verification & Final Results

| Metric | Initial State | Final State | Verification Method |
| :--- | :---: | :---: | :--- |
| **Free Storage** | 1.05 GB | **27.23 GB** | `Win32_LogicalDisk` query |
| **Idle CPU Load** | ~67% | **~19%** | `Win32_Processor` LoadPercentage |
| **Pagefile Size** | 14.03 GB | **4.00 GB** | Direct file system measure |
| **WSL RAM Limit** | 50% Host (~4GB) | **2.50 GB Hard Cap** | `.wslconfig` validation |
| **Git Status Latency**| ~850 ms | **<90 ms** | Multi-file benchmark |

---

## 5. Lessons Learned & System Architecture Takeaways

1. **Unbounded Virtual Memory is a Storage Hazard:** On small SSDs (128 GB), dynamic pagefiles combined with heavy compilation workloads will silently consume 10–15% of the drive. Static bounds are essential.
2. **Third-Party "RAM Cleaners" Cause Thrashing:** Tools that periodically force-purge the working set degrade system performance by forcing Windows to read evicted pages back from disk.
3. **Multi-Process Chromium Requires Policy Governance:** On multi-profile systems, Chromium will gladly consume all physical RAM unless tab discarding and cache caps are enforced via Enterprise Group Policy.
4. **Linux-in-Windows (WSL2) Must Have Resource Ceilings:** Always define a `.wslconfig` on machines with ≤ 16GB RAM to prevent hypervisor memory starvation.
