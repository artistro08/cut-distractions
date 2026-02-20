@echo off
REM ============================================================================
REM BUILD.bat
REM Simple launcher for the UIAccess build process (requires PowerShell 7)
REM ============================================================================

echo.
echo ============================================================
echo   CutDistractions - UIAccess Build Launcher
echo ============================================================
echo.
echo This will launch the PowerShell 7 build script with admin privileges.
echo.
echo Press any key to continue, or Ctrl+C to cancel...
pause >nul

REM Verify PowerShell 7 is available
where pwsh >nul 2>&1
if %errorLevel% neq 0 (
    echo ERROR: PowerShell 7 ^(pwsh^) not found.
    echo Please install it from: https://aka.ms/powershell
    echo.
    pause
    exit /b 1
)

REM Check if running as Administrator
net session >nul 2>&1
if %errorLevel% == 0 (
    echo Running as Administrator...
    echo.
    REM Already admin, run PowerShell 7 script directly
    pwsh -ExecutionPolicy Bypass -File "%~dp0BUILD-ALL.ps1"
) else (
    echo Requesting Administrator privileges...
    echo.
    REM Not admin, request elevation via PowerShell 7
    pwsh -Command "Start-Process pwsh -ArgumentList '-ExecutionPolicy Bypass -File ""%~dp0BUILD-ALL.ps1""' -Verb RunAs"
)

echo.
echo Build script launched!
echo Check the PowerShell window for progress.
echo.
pause
