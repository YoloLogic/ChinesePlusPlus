@echo off
rem ===========================================================================
rem  One-click setup for Chinese++.
rem
rem  Double-click this file. It runs install.ps1 with the execution policy
rem  bypassed for THIS process only -- nothing about your system policy changes.
rem
rem  What it will do (all of it inside this folder):
rem    * give the bundled compiler its other names (clang / clang-cl / ...)
rem    * write env.cmd, a window-scoped PATH setter
rem    * check for Visual Studio Build Tools and tell you exactly what to
rem      install if they are missing
rem    * download the official Visual Studio Code into .\vscode\ and set it up
rem      in PORTABLE mode (your own VS Code is never touched), with the Chinese
rem      language pack and clangd
rem    * compile and run a Chinese hello world to prove it works
rem
rem  This file is intentionally ASCII: cmd.exe reads it in the console code
rem  page (GBK on Chinese Windows), and non-ASCII here would be mangled.
rem ===========================================================================

setlocal
cd /d "%~dp0"

where powershell >nul 2>nul
if errorlevel 1 (
    echo.
    echo   PowerShell was not found on this system.
    echo   This setup needs Windows PowerShell, which ships with Windows.
    echo.
    pause
    exit /b 1
)

echo.
echo   Starting Chinese++ setup...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
set RC=%ERRORLEVEL%

echo.
if "%RC%"=="0" (
    echo   Setup finished successfully.
) else (
    echo   Setup reported a problem ^(exit code %RC%^).
    echo   Read the messages above.
)
echo.
pause
exit /b %RC%
