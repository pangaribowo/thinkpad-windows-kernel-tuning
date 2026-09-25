# Incident Post-Mortem & Architecture: NDIS 6.x Lightweight Filter Driver Collisions

**Incident Reference:** INC-20260915-NET-01  
**Severity:** High (Complete failure of Windows Internet Connection Sharing / Mobile Hotspot)  
**System Impact:** Mobile Hotspot terminated within 500ms of activation; host networking stack instability  
**Subsystem:** Windows NT Network Stack, NDIS 6.x, Internet Connection Sharing (`SharedAccess`), `ipnathlp.dll`

---

## 1. Executive Summary

During production workflows, activating the Windows 10 Mobile Hotspot feature failed instantly upon initialization. Detailed forensic analysis of the Windows Event Log identified an unhandled user-mode exception inside the Internet Connection Sharing (ICS) helper library `ipnathlp.dll` (`STATUS_ACCESS_VIOLATION` `0xc0000005`). 

Tracing the NDIS miniport and filter driver stack revealed that a residual third-party hypervisor driver—the **VirtualBox NDIS6 Bridged Networking Driver (`oracle_VBoxNetLwf`)**—remained bound as an active modifying Lightweight Filter (LWF) across all network adapters. When Windows attempted to bind virtual Wi-Fi Direct interfaces for SoftAP operation, `oracle_VBoxNetLwf` intercepted NDIS Object Identifier (OID) requests and passed corrupted or uninitialized `NET_BUFFER_LIST` descriptors, inducing an immediate null pointer dereference in user-mode.

Programmatically unbinding `oracle_VBoxNetLwf` across physical and virtual adapters fully restored Mobile Hotspot functionality without requiring a host reboot.

---

## 2. Architectural Root Cause Analysis

### 2.1 The Windows Mobile Hotspot Stack
Windows 10 implements Mobile Hotspot via a multi-tiered architecture:
1. **WLAN AutoConfig Service (`WlanSvc`):** Coordinates with the native Wi-Fi miniport driver (Intel Dual Band Wireless-AC 8260) to instantiate a virtual Wi-Fi Direct interface (`Local Area Connection* 12`).
2. **ICS / SharedAccess Service (`icssvc.dll`):** Provides network address translation (NAT), DNS proxying, and DHCP address assignment.
3. **NAT Helper Library (`ipnathlp.dll`):** Kernel-mode/user-mode gateway responsible for binding routing tables, DHCP leases, and port forwarding rules.

```
┌──────────────────────────────────────────────────────────────┐
│            USER-MODE SERVICES & ROUTING LOGIC                │
│  • icssvc.dll (ICS Controller)                               │
│  • ipnathlp.dll (NAT / DHCP Helper) ◄───[CRASH OCCURS HERE!] │
├──────────────────────────────────────────────────────────────┤
│                   TCP/IP PROTOCOL DRIVER                     │
├──────────────────────────────────────────────────────────────┤
│               NDIS LIGHTWEIGHT FILTER (LWF) TIER             │
│  • mpsdrv.sys (Windows Filtering Platform / Firewall)        │
│  • oracle_VBoxNetLwf (VirtualBox NDIS6 Filter) ◄──[FAULTY]   │
├──────────────────────────────────────────────────────────────┤
│                   NDIS MINIPORT DRIVERS                      │
│  • netwtw06.sys (Intel AC 8260 Wi-Fi 2 Miniport)             │
│  • vwifimp.sys (Microsoft Wi-Fi Direct Virtual Miniport)     │
└──────────────────────────────────────────────────────────────┘
```

### 2.2 Mechanism of the Access Violation (0xc0000005)
When `SharedAccess` activates:
1. Windows initializes a SoftAP BSSID and assigns an internal subnet (`192.168.137.1/24`).
2. `ipnathlp.dll` queries NDIS miniport characteristics via OID requests (`OID_GEN_NETWORK_LAYER_ADDRESSES`).
3. `oracle_VBoxNetLwf`, registered as a modifying filter driver, intercepts packet descriptors and OID queries.
4. Because virtual Wi-Fi Direct miniports dynamically alter MAC addresses and adapter capabilities, `oracle_VBoxNetLwf` encountered unexpected adapter states, failed its internal memory allocation, and returned an uninitialized context pointer in the `NET_BUFFER_LIST`.
5. When `ipnathlp.dll` attempted to dereference this pointer to initialize the DHCP listener socket, Windows raised exception `0xc0000005` (Null Pointer Dereference), killing the `SharedAccess` service process.

---

## 3. Forensic Log Evidence

### Windows System Event Log:
```text
Log Name:      System
Source:        Service Control Manager
Event ID:      7031
Level:         Error
Description:   The SharedAccess service terminated unexpectedly. It has done this 1 time(s).
               The following corrective action will be taken in 100 milliseconds: Restart the service.
```

### Windows Application Event Log:
```text
Log Name:      Application
Source:        Application Error
Event ID:      1000
Level:         Error
Description:   Faulting application name: svchost.exe_SharedAccess, version: 10.0.19041.1
               Faulting module name: ipnathlp.dll, version: 10.0.19041.4355
               Exception code: 0xc0000005
               Fault offset: 0x000000000000be43
               Faulting process id: 0x1bf4
```

---

## 4. Remediation & Verification Runbook

### Step 1: Enumerate Network Bindings
Query all active network adapters for residual filter drivers:
```powershell
Get-NetAdapterBinding | Where-Object { $_.ComponentID -like "*vbox*" -or $_.DisplayName -like "*VirtualBox*" } | Format-Table -AutoSize
```
*Identified `oracle_VBoxNetLwf` enabled across `vEthernet (WSL)`, `Ethernet 2`, `Wi-Fi 2`, and `Local Area Connection* 12`.*

### Step 2: Programmatically Decouple Filter Bindings
Execute administrative PowerShell commands to unbind the driver without disrupting active connections:
```powershell
$adapters = @("vEthernet (WSL)", "Ethernet 2", "Wi-Fi 2", "Local Area Connection* 12")
foreach ($adapter in $adapters) {
    Disable-NetAdapterBinding -Name $adapter -ComponentID "oracle_VBoxNetLwf" -ErrorAction SilentlyContinue
}
```

### Step 3: Disable Orphaned Host-Only Virtual Adapters
```powershell
Disable-NetAdapter -Name "Ethernet 3" -Confirm:$false -ErrorAction SilentlyContinue
```

### Step 4: Restart Network Sharing Services
```powershell
Restart-Service -Name "SharedAccess" -Force
Restart-Service -Name "icssvc" -Force
```

### Step 5: Empirical Verification via WinRT API
Trigger tethering programmatically and verify network state:
```powershell
[Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType = WindowsRuntime] | Out-Null
$connectionProfile = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType = WindowsRuntime]::GetInternetConnectionProfile()
$tetheringManager = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager]::CreateFromConnectionProfile($connectionProfile)
$result = $tetheringManager.StartTetheringAsync().GetAwaiter().GetResult()
Write-Host "Start Tethering Status: $($result.Status)"
```
**Output:** `Start Tethering Status: Success`  
**Live Client Verification:** Broadcasted SSID `DESKTOP-9HU6DH7 2167`, verified 1 active smartphone client connected with valid IP assignment (`192.168.137.x`) and bidirectional Internet routing.

---

## 5. Architectural Lessons Learned

1. **Hypervisor Teardown Completeness:** Deleting virtual machines via `VBoxManage` or GUI managers removes guest virtual disks but leaves kernel-mode host filter drivers bound. Hypervisor uninstalls or automated teardown scripts must verify `Get-NetAdapterBinding`.
2. **NDIS Filter Incompatibilities with Wi-Fi Direct:** Third-party filter drivers developed for standard 802.3 Ethernet or 802.11 Infrastructure miniports frequently exhibit edge-case crashes when confronted with 802.11 Virtual Wi-Fi Direct SoftAP interfaces.
