<#
.SYNOPSIS
    Chromium / Brave Browser Enterprise Policy Tuning
    Enforces Memory Saver (Tab Discarding), GPU Hardware Offloading, and Disk Cache Caps.
#>

Write-Host "=== Configuring Chromium / Brave Browser Policies ===" -ForegroundColor Cyan

$bravePolicy = "HKLM:\SOFTWARE\Policies\BraveSoftware\Brave"
if (-not (Test-Path $bravePolicy)) { New-Item -Path $bravePolicy -Force | Out-Null }

# 1. Enable Global Memory Saver (Tab Discarding)
Set-ItemProperty -Path $bravePolicy -Name "HighEfficiencyModeEnabled" -Value 1 -Type DWord
Write-Host "[OK] Memory Saver (Tab Discarding) locked to Active" -ForegroundColor Green

# 2. Enforce Hardware Acceleration on GPU
Set-ItemProperty -Path $bravePolicy -Name "HardwareAccelerationModeEnabled" -Value 1 -Type DWord
Write-Host "[OK] GPU Hardware Offload enabled" -ForegroundColor Green

# 3. Disk & Media Cache Caps (Prevent Multi-Gigabyte Bloat)
Set-ItemProperty -Path $bravePolicy -Name "DiskCacheSize" -Value 268435456 -Type DWord
Set-ItemProperty -Path $bravePolicy -Name "MediaCacheSize" -Value 134217728 -Type DWord
Write-Host "[OK] Disk Cache capped at 256MB per profile" -ForegroundColor Green

# 4. Exempt Brave Executable from Windows EcoQoS Power Throttling (Prevent MV3 Extension Service Worker Starvation)
$braveExe = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\Application\brave.exe"
if (Test-Path $braveExe) {
    powercfg /powerthrottling disable /path $braveExe 2>&1 | Out-Null
    Write-Host "[OK] Windows Power Throttling disabled for brave.exe (Never On)" -ForegroundColor Green
}

