@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0atualizar.ps1"
if errorlevel 1 pause
