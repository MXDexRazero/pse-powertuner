@echo off
setlocal
title PowerTune - Admin Runner

rem ==========================================================================
rem  PowerTune Admin Runner
rem
rem  Elevates (UAC) if needed, then starts the interactive menu:
rem      .\Show-PowerMenu.ps1
rem
rem  Menu items:
rem      1) One-click test  (.\Apply-PowerProfile.ps1 -Profile auto -IncludeDC
rem                          then .\Show-PowerReport.ps1 -Open)
rem      2) Backup sub-menu (list backups / rollback to latest / back)
rem      3) All commands    (script -> parameter -> value, then execute)
rem      0 / Esc) Exit
rem
rem  Usage:
rem      Run-PowerTune.bat              mouse + keyboard
rem      Run-PowerTune.bat -nomouse     keyboard only (if mouse misbehaves)
rem
rem  If the current session is not elevated, it re-launches itself with
rem  Start-Process -Verb RunAs (UAC prompt), then exits.
rem
rem  NOTE: this file is intentionally pure ASCII so cmd.exe decodes it
rem  correctly under any OEM code page (936 / 65001 / 437 ...).
rem  All Chinese text is rendered by the PowerShell menu script.
rem ==========================================================================

set "PSE_ROOT=%~dp0"
set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS_EXE%" set "PS_EXE=powershell.exe"

if not exist "%PSE_ROOT%Show-PowerMenu.ps1" (
  echo [ERROR] Show-PowerMenu.ps1 not found in %PSE_ROOT%
  echo.
  pause
  endlocal
  exit /b 1
)

rem --- privilege probe: exit 0 = admin, exit 1 = not admin ------------------
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -Command ^
  "$id=[Security.Principal.WindowsIdentity]::GetCurrent();" ^
  "$p=New-Object Security.Principal.WindowsPrincipal($id);" ^
  "if($p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){exit 0}else{exit 1}"
if errorlevel 1 goto :ELEVATE

:RUN
rem Pass -nomouse to force keyboard-only mode (escape hatch if mouse fails)
set "MENU_ARG="
if /i "%~1"=="-nomouse" set "MENU_ARG=-NoMouse"
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%PSE_ROOT%Show-PowerMenu.ps1" %MENU_ARG%
endlocal
exit /b 0

:ELEVATE
echo Requesting administrator privileges (UAC) ...
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -Command ^
  "try{Start-Process -FilePath '%~f0' -Verb RunAs -ErrorAction Stop;exit 0}catch{exit 1}"
if errorlevel 1 (
  echo.
  echo [ERROR] Elevation failed or was cancelled.
  echo         Right-click this file and choose "Run as administrator".
  echo.
  pause
  endlocal
  exit /b 1
)
endlocal
exit /b 0
