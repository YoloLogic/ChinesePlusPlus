@echo off
rem ===========================================================================
rem  One-click: make YOUR OWN VS Code understand Chinese++.
rem
rem  WHAT IT DOES
rem    * backs up your VS Code user settings.json
rem    * points clangd at the clangd that ships in this folder
rem      (the stock clangd does NOT know Chinese keywords)
rem    * installs the clangd extension if you do not have it
rem
rem  TO UNDO: run the one-click RESTORE script in this folder.
rem
rem  It does NOT touch the portable editor inside this folder, and it does not
rem  change anything else in your settings.
rem
rem  The Chinese explanation of this operation is in the .md documents next to
rem  this file. This file is ASCII on purpose: cmd.exe reads it in the console
rem  code page (GBK on Chinese Windows) and non-ASCII here would be mangled.
rem ===========================================================================

setlocal
cd /d "%~dp0"

where powershell >nul 2>nul
if errorlevel 1 (
    echo.
    echo   PowerShell was not found on this system.
    echo.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0attach-to-vscode.ps1"
set RC=%ERRORLEVEL%

echo.
if "%RC%"=="0" (
    echo   Finished.
) else (
    echo   Something went wrong ^(exit code %RC%^). Read the messages above.
)
echo.
pause
exit /b %RC%
