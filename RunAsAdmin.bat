@echo off
setlocal EnableDelayedExpansion
title Run PowerShell as Admin

REM ============================================================
REM  DRAG-AND-DROP POWERSHELL RUNNER (Bulletproof version)
REM  Handles paths with spaces by using a temp file for the path
REM ============================================================

set "TEMP_PATH_FILE=%TEMP%\RunAsAdmin_script_path.txt"
set "PS_SCRIPT="

REM ---------- Check for internal elevated flag ----------
if /i "%~1"=="--elevated" goto :RUN_ELEVATED

REM ---------- Get the dropped file path ----------
if not "%~1"=="" (
    REM Use %* to grab ALL args in case spaces split them, then strip quotes
    set "RAW=%~f1"
    REM Re-check: if path doesn't end in .ps1, try joining %* to handle spaces
    echo !RAW! | find /i ".ps1" >nul
    if errorlevel 1 (
        REM Path was split — join all args with spaces
        set "RAW=%~dp0"
        set "RAW="
        for %%A in (%*) do set "RAW=!RAW! %%A"
        set "RAW=!RAW:~1!"
    )
    set "PS_SCRIPT=!RAW!"
) else (
    REM ---------- No file dropped: open a file picker ----------
    echo ========================================================
    echo  NO FILE DROPPED - OPENING FILE PICKER...
    echo ========================================================
    echo.
    for /f "usebackq delims=" %%F in (`powershell -NoProfile -Command "Add-Type -AssemblyName System.Windows.Forms; $f = New-Object System.Windows.Forms.OpenFileDialog; $f.Filter = 'PowerShell Scripts (*.ps1)|*.ps1'; $f.Title = 'Select a PowerShell script to run as Admin'; if ($f.ShowDialog() -eq 'OK') { Write-Output $f.FileName }"`) do set "PS_SCRIPT=%%F"
)

REM ---------- Validate ----------
if "!PS_SCRIPT!"=="" (
    echo.
    echo No file selected. Exiting.
    pause
    exit /b 1
)

if not exist "!PS_SCRIPT!" (
    echo ========================================================
    echo  ERROR: File not found:
    echo  !PS_SCRIPT!
    echo ========================================================
    pause
    exit /b 1
)

echo !PS_SCRIPT! | find /i ".ps1" >nul
if errorlevel 1 (
    echo ========================================================
    echo  ERROR: Not a .ps1 PowerShell script.
    echo  File: !PS_SCRIPT!
    echo ========================================================
    pause
    exit /b 1
)

REM ---------- Save path to temp file BEFORE elevating ----------
echo !PS_SCRIPT!>"%TEMP_PATH_FILE%"

REM ---------- Elevate if not admin ----------
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting Administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '--elevated' -Verb RunAs"
    exit /b
)

REM ---------- Already admin: read path from temp file and run ----------
:RUN_ELEVATED
if exist "%TEMP_PATH_FILE%" (
    set /p PS_SCRIPT=<"%TEMP_PATH_FILE%"
    del "%TEMP_PATH_FILE%" >nul 2>&1
)

if "!PS_SCRIPT!"=="" (
    echo ERROR: Could not retrieve script path.
    pause
    exit /b 1
)

color 0A
cls
echo ========================================================
echo  RUNNING POWERSHELL SCRIPT AS ADMINISTRATOR
echo.
echo  File: !PS_SCRIPT!
echo ========================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "!PS_SCRIPT!"

echo.
echo ========================================================
echo  SCRIPT FINISHED
echo ========================================================
pause