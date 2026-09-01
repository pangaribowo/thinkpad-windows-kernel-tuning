@echo off
title Windows Performance Optimizer - System Health Status
color 0A
echo.
echo   ==============================================
echo     Windows Workstation Health Diagnostics
echo   ==============================================
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0..\scripts\optimize.ps1" -Mode Status
echo.
echo   ==============================================
echo   Press any key to exit...
pause > nul
