@echo off
rem ===========================================================================
rem  One-click: put YOUR OWN VS Code back the way it was.
rem
rem  WHAT IT DOES
rem    * restores your VS Code user settings.json from the backup that the
rem      attach script made
rem    * if you had no settings.json before, removes the one that was created
rem
rem  WHAT IT DOES NOT DO
rem    * it does not uninstall the clangd extension -- remove it yourself from
rem      the Extensions panel if you do not want it
rem    * it does not touch the portable editor inside this folder
rem
rem  The Chinese explanation is in the .md documents next to this file.
rem  This file is ASCII on purpose (see the attach script for why).
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

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0detach-from-vscode.ps1"
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
