# System Architecture & Windows Kernel Internals (v2.0)

This document provides a low-level engineering deep-dive into the Windows NT operating system internals, memory management algorithms, kernel scheduling mechanics, network filter drivers, and file system compression tuned in this repository.

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

### `Win32PrioritySeparation` Mechanics
Located at: `HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl`

The 6-bit mask of `Win32PrioritySeparation` determines three core scheduling parameters:

| Bit Range | Configuration Field | Default (2) | Tuned Value: `26` (`0x1A` / `0b011010`) | Impact |
| :--- | :--- | :---: | :---: | :--- |
| **Bits 0–1** | **Quantum Length** | Variable (`0b10`) | Short (`0b10`) | Shorter thread execution slices (6 clock ticks) |
| **Bits 2–3** | **Variable vs Fixed** | Variable (`0b01`) | Variable (`0b01`) | Foreground threads receive variable quantum extension |
| **Bits 4–5** | **Foreground Boost Ratio** | 3:1 Boost (`0b01`)| **3:1 Maximum Boost (`0b01`)** | Active foreground window receives **3x more CPU time slices** |

**Engineering Value:** Eliminates input latency and GUI stuttering when switching rapidly between IDE editor windows, terminal sessions, and browser devtools on a dual-core / quad-thread CPU.

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

### The Dynamic Pagefile Trap & Bounded Mitigation
Under default configurations, Windows dynamically increases `pagefile.sys` when application commit charges spike:
1. Windows rarely shrinks an inflated pagefile dynamically during a running session.
2. Dynamic growth causes continuous file system fragmentation on the SSD.
3. On a 128 GB drive, a 14 GB pagefile consumes over **11.7% of total disk capacity**.

**Remediation:** Setting a **Fixed Bounded Pagefile (4,096 MB min / 8,192 MB max)**:
* Prevents runaway expansion during heavy memory-intensive builds.
* Eliminates pagefile fragmentation.
* Guarantees that at least 6.0+ GB of SSD space is permanently reclaimed.

### Kernel Executive Lock (`DisablePagingExecutive = 1`)
Located at: `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management`

* **Default (`0`):** In low-memory scenarios (<15% free RAM), Windows pages out kernel-mode drivers and system code (`ntoskrnl.exe`, file system filter drivers) into `pagefile.sys`.
* **Tuned (`1`):** Completely disables paging of executive subsystems and kernel-mode drivers, forcing them to remain resident in physical RAM.
* **Impact:** When a user switches back to an editor or initiates disk I/O, the kernel does not incur page faults or wait for SSD read operations, resulting in immediate input responsiveness.

---

## 3. CompactOS: Kernel-Level NTFS System Compression

Windows 10 introduces **CompactOS**, an evolution of WIMBoot that transparently compresses operating system binaries directly on the NTFS file system.

```
┌─────────────────────────────────────────────────────────────┐
│                 USER PROCESS (e.g., Code.exe)               │
│                            │                                │
│                   Read File (e.g., ntdll.dll)               │
│                            ▼                                │
├─────────────────────────────────────────────────────────────┤
│                    NTFS DRIVER (ntfs.sys)                   │
│   Detects File System Reparse Point (IO_REPARSE_TAG_WOF)    │
│                            │                                │
│                  Hands off to WOF.SYS                       │
├─────────────────────────────────────────────────────────────┤
│              WINDOWS OVERLAY FILTER (wof.sys)               │
│        Decompresses XPRESS / LZX Block in Memory            │
│                            │                                │
│              Decompressed Data Returned to RAM              │
├─────────────────────────────────────────────────────────────┤
│                     PHYSICAL NAND FLASH                     │
│    Reads 40% - 60% FEWER Physical Sectors from Disk!        │
└─────────────────────────────────────────────────────────────┘
```

### Algorithm Comparison
CompactOS utilizes four compression algorithms supported natively by `wof.sys`:
1. **XPRESS4K / XPRESS8K:** Fast LZ77-variant compression optimized for maximum decompression throughput with near-zero CPU cycles.
2. **XPRESS16K:** Higher compression ratio with balanced throughput.
3. **LZX:** High-ratio Huffman-variant compression reserved for rarely modified, large system assemblies.

**Why CompactOS Accelerates Low-Spec Workstations:**
On DRAM-less or entry-level SSDs (such as the SanDisk 128GB SATA SSD in this study), **storage bus bandwidth and sequential NAND read IOPS are primary bottlenecks**. Because decompression occurs at CPU cache speeds (>5 GB/s via Intel Skylake SSE4.2 instructions), reading smaller compressed blocks from the physical SSD is frequently **faster than reading uncompressed files**, while permanently releasing **2.5 to 4.0 GB of storage**.

---

## 4. NDIS 6.x Lightweight Filter (LWF) vs Miniport Binding Architecture

Network Driver Interface Specification (NDIS) version 6.x structures the Windows network stack into layered driver tiers:

```
┌──────────────────────────────────────────────────────────────┐
│                    TCP/IP PROTOCOL STACK                     │
├──────────────────────────────────────────────────────────────┤
│               NDIS LIGHTWEIGHT FILTERS (LWFs)                │
│  • Windows Filtering Platform (WFP / mpsdrv.sys)             │
│  • VirtualBox NDIS6 Filter Driver (oracle_VBoxNetLwf) ◄──[!]-│ (Interception)
├──────────────────────────────────────────────────────────────┤
│                   NDIS MINIPORT DRIVERS                      │
│  • Intel Dual Band Wireless-AC 8260 (Wi-Fi 2)                │
│  • Hyper-V Virtual Switch (vEthernet WSL)                    │
│  • Wi-Fi Direct Virtual Adapter (SoftAP / Hotspot)           │
├──────────────────────────────────────────────────────────────┤
│                     PHYSICAL HARDWARE / PHY                  │
└──────────────────────────────────────────────────────────────┘
```

### The Root Cause of `ipnathlp.dll` Access Violation (0xc0000005)
When Windows Internet Connection Sharing (ICS / `SharedAccess`) initializes a Mobile Hotspot:
1. `icssvc.dll` creates a virtual SoftAP interface on top of the Wi-Fi Direct adapter.
2. The user-mode NAT/DHCP library `ipnathlp.dll` issues IOCTL commands down the NDIS stack to bind IP forwarding rules.
3. Because `oracle_VBoxNetLwf` registered itself as a mandatory modifying filter across all network adapters, it intercepted the NDIS OID requests destined for the Wi-Fi Direct adapter.
4. When `oracle_VBoxNetLwf` encountered non-standard virtual miniport descriptors generated by Wi-Fi Direct, it failed to populate the `NET_BUFFER_LIST` context pointer, passing an uninitialized memory descriptor up to `ipnathlp.dll`.
5. `ipnathlp.dll` attempted to dereference the null context pointer, causing an immediate kernel user-mode crash (`STATUS_ACCESS_VIOLATION` `0xc0000005`), terminating the hotspot service.

**Remediation Architecture:** Programmatically unbinding `oracle_VBoxNetLwf` from `vEthernet (WSL)`, `Ethernet 2`, `Wi-Fi 2`, and `Local Area Connection* 12` removes the faulty filter layer completely from the packet traversal path, restoring raw, zero-overhead NDIS miniport communication.

---

## 5. Win32 Raw Input Architecture & Desktop Composition Latency

Input responsiveness in Windows is governed by the User subsystem (`user32.dll`) and Desktop Window Manager (`dwm.exe`):

```
[Keyboard Hardware Interrupt (IRQ 1)]
              │
              ▼
[i8042prt.sys / kbdclass.sys] (Translates Scan Codes)
              │
              ▼
[Raw Input Thread (RIT) in win32k.sys]
              │  ◄── Enforces KeyboardDelay & KeyboardSpeed!
              ▼
[System Message Queue]
              │
              ▼
[Application Message Loop (GetMessage / DispatchMessage)]
              │
              ▼
[DWM GPU Frame Rendering (dwm.exe)]
```

### Tuned Parameters
1. **`KeyboardDelay = 0`:** In the Windows input subsystem, `KeyboardDelay` values map to initial repeat hesitance timers:
   * Value `3`: ~1,000 ms delay
   * Value `1` (Default): ~500 ms delay
   * **Value `0` (Tuned):** ~250 ms delay (Minimal hardware debouncing threshold; provides instant typing feedback in code editors).
2. **`KeyboardSpeed = 31`:** Sets the auto-repeat frequency to the hardware maximum of **30 characters per second**.
3. **`MenuShowDelay = 0`:** Eliminates the legacy 400ms timer in `win32k.sys` before hover menus, context menus, and toolbars render.
4. **`MinAnimate = 0`:** Disables window transformation matrix calculations in the Desktop Window Manager, eliminating GPU frame drops during rapid window toggling on integrated Intel HD Graphics.

---

## 6. WSL2 Hyper-V Memory Architecture & Dynamic Reclamation

WSL2 executes a custom Linux Kernel inside a lightweight Hyper-V Virtual Machine (`vmmem`):

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

## 7. TCP/IP Network Stack: Compound TCP (CTCP) vs NewReno

The standard Windows TCP stack defaults to NewReno, which uses a purely loss-based congestion detection mechanism. In modern multi-tab, API-heavy development environments, this results in bufferbloat and suboptimal throughput.

```
Congestion Window (CWND)
▲
│        /│        /│        /│   ◄── NewReno (Loss-based sawtooth)
│       / │       / │       / │
│      /  │      /  │      /  │
│  ───/───┼─────/───┼─────/───┼── ◄── Compound TCP (Delay-based + Loss-based)
│    /    │    /    │    /    │       Predicts congestion before packet drop!
└─────────────────────────────────► Time
```

By activating **Compound TCP (CTCP)** via `netsh int tcp set supplemental template=custom congestionprovider=ctcp`, the kernel maintains two state windows:
1. A standard loss-based window ($cwnd$).
2. A delay-based window ($dwnd$) monitoring Round Trip Time (RTT) variations.

When latency spikes are detected, CTCP scales back transmission preemptively without waiting for packet drops or TCP retransmissions, maintaining lower queue latency during concurrent operations.
