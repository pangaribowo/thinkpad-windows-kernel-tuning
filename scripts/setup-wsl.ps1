<#
.SYNOPSIS
    WSL2 & Docker Desktop Resource Limiter
    Deploys .wslconfig to prevent Linux hypervisor memory starvation on the Windows host.
#>

Write-Host "=== Configuring WSL2 / Docker Resource Management ===" -ForegroundColor Cyan

$wslConfigPath = "$env:USERPROFILE\.wslconfig"
$wslContent = @"
# Global WSL2 & Docker Desktop Engine Optimization
[wsl2]
# Hard memory upper-bound for Linux micro-VM (2.5 GB)
memory=2560MB
# Limit core usage to 2 CPU threads
processors=2
# Virtual swap partition (2 GB)
swap=2048MB
# Force Linux kernel to return free page frames dynamically to Windows
pageReporting=true
# Disable unused WSLg GUI subsystems
guiApplications=false

[experimental]
# Gradually reclaim unused container cache
autoMemoryReclaim=gradual
"@

Set-Content -Path $wslConfigPath -Value $wslContent -Encoding UTF8 -Force
Write-Host "[OK] .wslconfig deployed successfully at: $wslConfigPath" -ForegroundColor Green
Write-Host "[INFO] WSL2 memory is capped at 2.50 GB with dynamic page reporting." -ForegroundColor Gray
