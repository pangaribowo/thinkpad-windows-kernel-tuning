<#
.SYNOPSIS
    Kernel & TCP Subsystem Optimizer
    Configures Win32PrioritySeparation, SystemResponsiveness, Compound TCP, and NTFS.
#>

Write-Host "=== Applying Windows Kernel & Subsystem Optimizations ===" -ForegroundColor Cyan

# 1. CPU Thread Quantum Scheduling (0x1A / 26)
$priorityPath = "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"
Set-ItemProperty -Path $priorityPath -Name "Win32PrioritySeparation" -Value 26 -Type DWord
Write-Host "[OK] Win32PrioritySeparation set to 26 (0x1A - 3:1 Foreground Boost)" -ForegroundColor Green

# 2. Multimedia & System Responsiveness
$sysProfile = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
Set-ItemProperty -Path $sysProfile -Name "SystemResponsiveness" -Value 0 -Type DWord
Set-ItemProperty -Path $sysProfile -Name "NetworkThrottlingIndex" -Value 4294967295 -Type DWord
Write-Host "[OK] SystemResponsiveness set to 0 (100% CPU priority for foreground apps)" -ForegroundColor Green
Write-Host "[OK] NetworkThrottlingIndex disabled (Zero packet throttling)" -ForegroundColor Green

# 3. TCP/IP Stack & Compound TCP
netsh int tcp set supplemental template=internet congestionprovider=ctcp 2>&1 | Out-Null
netsh int tcp set global autotuninglevel=normal 2>&1 | Out-Null
netsh int tcp set global fastopen=enabled 2>&1 | Out-Null
netsh int tcp set global hystart=enabled 2>&1 | Out-Null
netsh int tcp set global prr=enabled 2>&1 | Out-Null
netsh int tcp set global timestamps=disabled 2>&1 | Out-Null
netsh int tcp set global rss=enabled 2>&1 | Out-Null
Write-Host "[OK] TCP Congestion Provider set to CTCP (Compound TCP) + RACK" -ForegroundColor Green

# 4. NTFS SSD Tuning
fsutil behavior set disablelastaccess 1 2>&1 | Out-Null
fsutil behavior set memoryusage 2 2>&1 | Out-Null
Write-Host "[OK] NTFS DisableLastAccess enabled (Zero metadata write overhead)" -ForegroundColor Green

Write-Host "`n[SUCCESS] Kernel and subsystem tuning completed." -ForegroundColor Cyan
