@echo off
title Launch Next Virtual Counter
echo ===================================================
echo   PHARMA PRO ERP - Multi-Counter Auto-Scaler
echo ===================================================
echo.

powershell -ExecutionPolicy Bypass -File "%~dp0launch_next_counter.ps1"

echo.
echo ===================================================
timeout /t 2 >nul
