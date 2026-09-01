@echo off
title Windows Performance Optimizer - Clean Mode
color 0B
echo.
echo   ==============================================
echo     Windows Routine Performance Scrubber
echo   ==============================================
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0..\scripts\optimize.ps1" -Mode Clean
echo.
echo   ==============================================
echo   Press any key to exit...
pause > nul
