@echo off
rem One-click: write this package's editor config into a folder you choose.
rem Pick the folder you OPEN in VS Code (the workspace root).
rem Pure ASCII on purpose (PowerShell 5.1 reads BOM-less files as GBK).
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0configure-workspace.ps1" %*
echo.
pause
