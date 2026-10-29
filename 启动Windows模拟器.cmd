@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0x86\start-windows.ps1"
if errorlevel 1 pause
