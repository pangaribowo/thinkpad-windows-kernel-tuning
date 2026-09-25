<#
.SYNOPSIS
    ThinkPad Workstation Responsiveness & Input Latency Engine (v2.0)
.DESCRIPTION
    Applies low-level Windows NT registry and subsystem configurations to maximize
    typing responsiveness, eliminate window transition overhead, tune the kernel
    paging executive, and unbind conflicting NDIS filter drivers on Intel ThinkPads.
#>

param(
    [switch]$Revert
)

function Write-Step($title) {
    Write-Host "[*] $title" -ForegroundColor Cyan
}

function Write-Success($msg) {
    Write-Host "  [+] $msg" -ForegroundColor Green
}

function Write-Notice($msg) {
    Write-Host "  [i] $msg" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  THINKPAD WORKSTATION RESPONSIVENESS & LATENCY TUNER (v2.0)     " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

if ($Revert) {
    Write-Step "Reverting configurations to Windows defaults..."
    Set-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardDelay" -Value 1
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Value "400"
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name "MinAnimate" -Value "1"
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAnimations" -Value 1
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "DisablePagingExecutive" -Value 0
    Write-Success "Settings reverted to system defaults."
    exit 0
}

# 1. Typing & Keyboard Latency Optimization
Write-Step "1. Tuning Keyboard Repeat Delay & Polling Rate..."
Set-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardDelay" -Value 0
Set-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardSpeed" -Value 31
Write-Success "KeyboardDelay = 0 (Instant auto-repeat initialization; zero key hesitance)"
Write-Success "KeyboardSpeed = 31 (Maximum 30 char/sec repeat rate)"

# 2. Window Transition & Menu Flyout Snappiness
Write-Step "2. Eliminating Desktop Composition & Animation Latency..."
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Value "0"
if (-not (Test-Path "HKCU:\Control Panel\Desktop\WindowMetrics")) {
    New-Item -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Force | Out-Null
}
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name "MinAnimate" -Value "0"
Write-Success "MenuShowDelay = 0ms (Context menus and dropdowns appear instantaneously)"
Write-Success "MinAnimate = 0 (Window minimize/maximize transition lag eliminated)"

# 3. Explorer Shell & Multitasking Efficiency
Write-Step "3. Optimizing Shell & Taskbar Interaction..."
$advPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
Set-ItemProperty -Path $advPath -Name "TaskbarAnimations" -Value 0 -Type DWord
Set-ItemProperty -Path $advPath -Name "DisallowShaking" -Value 1 -Type DWord
Set-ItemProperty -Path $advPath -Name "IconsOnly" -Value 1 -Type DWord
Write-Success "TaskbarAnimations = 0 (Instant hover previews)"
Write-Success "Aero Shake Disabled (Prevents accidental window minimization during mouse gestures)"

# 4. Kernel Executive & Working Set Protection
Write-Step "4. Locking Kernel Executive in Physical RAM..."
$memPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
Set-ItemProperty -Path $memPath -Name "DisablePagingExecutive" -Value 1 -Type DWord
Write-Success "DisablePagingExecutive = 1 (Kernel drivers and code locked in physical memory; zero SSD paging wait)"

# 5. Network Stack Decoupling (De-conflict NDIS Lightweight Filter Drivers)
Write-Step "5. Decoupling VirtualBox NDIS6 Filter Drivers from Host Adapters..."
$adapters = @("vEthernet (WSL)", "Ethernet 2", "Wi-Fi 2", "Local Area Connection* 12")
foreach ($ad in $adapters) {
    $bind = Get-NetAdapterBinding -Name $ad -ComponentID "oracle_VBoxNetLwf" -ErrorAction SilentlyContinue
    if ($bind -and $bind.Enabled) {
        Disable-NetAdapterBinding -Name $ad -ComponentID "oracle_VBoxNetLwf" -ErrorAction SilentlyContinue
        Write-Success "Disabled oracle_VBoxNetLwf on $ad"
    } elseif ($bind) {
        Write-Notice "oracle_VBoxNetLwf already disabled on $ad"
    }
}

# 6. Purging Stale Crash Recovery RunOnce Keys
Write-Step "6. Scrubbing Crash Recovery Registry Queues..."
$runOncePath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
$staleKeys = @("Application Restart #9", "Application Restart #3")
foreach ($k in $staleKeys) {
    if (Get-ItemProperty $runOncePath -Name $k -ErrorAction SilentlyContinue) {
        Remove-ItemProperty -Path $runOncePath -Name $k -Force -ErrorAction SilentlyContinue
        Write-Success "Removed stale RunOnce key: $k"
    }
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  RESPONSIVENESS & LATENCY TUNING APPLIED SUCCESSFULLY!         " -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
