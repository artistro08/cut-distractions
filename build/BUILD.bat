@echo off
REM ============================================================================
REM BUILD.bat
REM Simple launcher for the UIAccess build process
REM ============================================================================

echo.
echo ============================================================
echo   CutDistractions - UIAccess Build Launcher
echo ============================================================
echo.
echo This will launch the PowerShell build script with admin privileges.
echo.
echo Press any key to continue, or Ctrl+C to cancel...
pause >nul

REM Check if running as Administrator
net session >nul 2>&1
if %errorLevel% == 0 (
    echo Running as Administrator...
    echo.
    REM Already admin, run PowerShell script directly
    powershell -ExecutionPolicy Bypass -File "%~dp0BUILD-ALL.ps1"
) else (
    echo Requesting Administrator privileges...
    echo.
    REM Not admin, request elevation
    powershell -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -File \"%~dp0BUILD-ALL.ps1\"' -Verb RunAs"
)

echo.
echo Build script launched!
echo Check the PowerShell window for progress.
echo.
pause
