@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Update-Addons.ps1" -Profile era -Addon BrutefistDeathReview
pause
