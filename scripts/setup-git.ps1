<#
.SYNOPSIS
    Git for Windows Multi-Threaded Engine Accelerator
    Enables fscache, multi-threaded index preloading, and untracked caching.
#>

Write-Host "=== Accelerating Git Engine for Windows NTFS ===" -ForegroundColor Cyan

git config --global core.fscache true
git config --global core.preloadindex true
git config --global core.untrackedCache true
git config --global feature.manyFiles true
git config --global gc.auto 256

Write-Host "[OK] core.fscache enabled (Memory metadata cache)" -ForegroundColor Green
Write-Host "[OK] core.preloadindex enabled (Parallel multi-threaded stat() scanning)" -ForegroundColor Green
Write-Host "[OK] feature.manyFiles enabled (Optimized for large repositories)" -ForegroundColor Green
