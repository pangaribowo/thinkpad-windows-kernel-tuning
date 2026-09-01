# System Architecture & Windows Kernel Internals

This document details the low-level operating system mechanics, kernel structures, memory management algorithms, and networking protocols tuned during this optimization project.

---

## 1. Windows NT Kernel Quantum & CPU Thread Scheduling

The Windows NT Executive Scheduler operates on a preemptive, priority-based thread scheduling model comprising 32 priority levels (0 to 31):
* **0–15:** Dynamic Priority Levels (User applications, interactive GUI, worker threads)
* **16–31:** Real-Time Priority Levels (Kernel drivers, hardware interrupts, audio clock sync)

```
Priority Level 31 ┌──────────────────────────────────────────────┐ (Real-Time)
                  │ Hardware Drivers, Clock Interrupts, DPC/ISR  │
Priority Level 16 ├──────────────────────────────────────────────┤
                  │ Foreground Interactive Process Threads       │ (Boosted via 0x1A)
Priority Level 8  ├──────────────────────────────────────────────┤ (Normal Base)
                  │ Background Services & Telemetry (DiagTrack)  │
Priority Level 0  └──────────────────────────────────────────────┘ (Idle)
```

### `Win32PrioritySeparation` Deep-Dive
Located at: `HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl`

The 6-bit mask of `Win32PrioritySeparation` determines three core scheduling parameters:

| Bit Range | Configuration Field | Default (2) | Tuned Value: `26` (`0x1A` / `0b011010`) | Impact |
| :--- | :--- | :---: | :---: | :--- |
| **Bits 0–1** | **Quantum Length** | Variable (`0b10`) | Short (`0b10`) | Shorter thread execution slices (6 clock ticks) |
| **Bits 2–3** | **Variable vs Fixed** | Variable (`0b01`) | Variable (`0b01`) | Foreground threads receive variable quantum extension |
| **Bits 4–5** | **Foreground Boost Ratio** | 3:1 Boost (`0b01`)| **3:1 Maximum Boost (`0b01`)** | Active foreground window receives **3x more CPU time slices** |

**Engineering Benefit:** Eliminates input latency and GUI stuttering when switching rapidly between IDE editor windows, terminal sessions, and browser devtools on a dual-core / quad-thread CPU.

---

## 2. Memory Subsystem & Virtual Memory Paging Dynamics

Windows manages physical RAM using a page-frame database divided into distinct lists:

```
[In-Use Pages] ──(Evicted)──> [Modified List] ──(Lazy Writer)──> [Pagefile.sys]
      │                                                               │
      ▼                                                               ▼
[Standby List] ──(Fault / Re-reference)───────────────────────> [In-Use Pages]
      │
      ▼ (Freed for immediate allocation)
[Free / Zeroed List]
```

### The Dynamic Pagefile Trap
Under default configurations, Windows dynamically increases `pagefile.sys` when application commit charges spike. However:
1. Windows rarely shrinks an inflated pagefile dynamically during a running session.
2. Dynamic growth causes continuous file system fragmentation on the SSD.
3. On a 128 GB drive, a 14 GB pagefile consumes over **11.7% of total disk capacity**.

**Solution:** By setting a **Fixed Bounded Pagefile (4,096 MB min / 8,192 MB max)**:
* Prevents runaway expansion during heavy memory-intensive builds.
* Eliminates pagefile fragmentation.
* Guarantees that at least 6.0+ GB of SSD space is permanently reclaimed.

---

## 3. WSL2 Hyper-V Memory Architecture & Dynamic Reclamation

WSL2 does not run as a compatibility layer (like WSL1); it executes an optimized Linux Kernel inside a lightweight Hyper-V Virtual Machine (`vmmem`).

```
┌─────────────────────────────────────────────────────────────┐
│                    HOST OS (WINDOWS 10)                     │
│  Available Physical Memory: 8.00 GB                         │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │               WSL2 Linux Micro-VM (Hyper-V)           │  │
│  │  Unconstrained: Allocates up to 50% Host RAM (4.0 GB) │  │
│  │  Tuned with .wslconfig: Capped strictly at 2.50 GB     │  │
│  │                                                       │  │
│  │  [PageReporting: Enabled]                             │  │
│  │  Linux Kernel ──(Free Pages)──> Hyper-V Balloon ────> │  │
│  │                                 Returned to Windows!  │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### Key `.wslconfig` Directives
* `memory=2560MB`: Enforces a hard physical upper bound.
* `processors=2`: Prevents container compilation from starving Windows UI threads.
* `pageReporting=true`: Enables virtio-balloon memory communication, allowing the Linux kernel to report unused page frames back to the Windows memory manager in real time.
* `autoMemoryReclaim=gradual`: Incrementally trims cached memory from idle containers.

---

## 4. TCP/IP Network Stack: Compound TCP (CTCP) vs NewReno

The standard Windows TCP stack defaults to NewReno, which uses a purely loss-based congestion detection mechanism. In modern multi-tab, API-heavy development environments, this results in bufferbloat and suboptimal throughput.

```
Congestion Window (CWND)
▲
│         /│        /│  (CTCP: Proactively tracks Delay-Based + Loss-Based)
│        / │       / │   Maintains higher average CWND without packet drops!
│       /  │      /  │
│  ────/───┴─────/───┴──────── (NewReno: Drastic 50% CWND halving on drop)
└────────────────────────────────────────► Time
```

### Applied TCP Subsystem Parameters:
* **Congestion Provider:** `CTCP` (Compound TCP) — Combines delay-based window adjustments with loss-based detection, maximizing bandwidth utilization on high-speed broadband.
* **RACK (Recent ACKs):** Uses time-based loss recovery rather than counting duplicate ACKs, significantly reducing TCP retransmission timeouts.
* **Receive Segment Coalescing (RSC):** Offloads TCP packet aggregation to network hardware, minimizing CPU interrupt overhead.

---

## 5. File System Optimization (NTFS vs Git Engine)

### 1. `DisableLastAccess = 1`
By default, NTFS updates the `LastAccessTime` attribute on every single file read operation. When an IDE indexes a repository containing 15,000 files, Windows executes 15,000 metadata write operations to the SSD. Disabling this eliminates zero-value write I/O and preserves SSD NAND lifespan.

### 2. Multi-Threaded Git Engine
* `core.fscache = true`: Caches directory and file existence queries in system memory.
* `core.preloadindex = true`: Distributes file stat calls across all 4 logical CPU threads in parallel during `git status` and `git diff`.
* `feature.manyFiles = true`: Optimizes Git index traversal algorithms for large JavaScript/Node.js repositories with thousands of source files.
