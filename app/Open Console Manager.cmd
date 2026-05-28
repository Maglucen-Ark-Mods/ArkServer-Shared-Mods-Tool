@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Sync-ASCTSharedMods.ps1"
