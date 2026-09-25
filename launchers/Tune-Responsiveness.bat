@echo off
:: ==============================================================
:: ThinkPad Workstation Responsiveness & Latency Tuner (v2.0)
:: 1-Click Administrative Execution Wrapper
:: ==============================================================
title ThinkPad Workstation Responsiveness Tuner
cd /d "%~dp0.."
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\tune-responsiveness.ps1"
echo.
pause
