# ============================================================================
# BUILD-ALL.ps1
# Master build script - Runs all steps to create a UIAccess-enabled executable
# ============================================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  CutDistractions - Complete UIAccess Build Process" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This script will:" -ForegroundColor White
Write-Host "  1. Create a self-signed code signing certificate" -ForegroundColor Gray
Write-Host "  2. Compile the AHK script with UIAccess manifest" -ForegroundColor Gray
Write-Host "  3. Sign the executable" -ForegroundColor Gray
Write-Host "  4. Deploy to Program Files" -ForegroundColor Gray
Write-Host ""

# Check if running as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    Write-Host "ERROR: This script must be run as Administrator!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please follow these steps:" -ForegroundColor Yellow
    Write-Host "  1. Right-click on PowerShell" -ForegroundColor Cyan
    Write-Host "  2. Select 'Run as Administrator'" -ForegroundColor Cyan
    Write-Host "  3. Navigate to this directory" -ForegroundColor Cyan
    Write-Host "  4. Run this script again" -ForegroundColor Cyan
    Write-Host ""
    Read-Host -Prompt "Press Enter to exit"
    exit 1
}

$scriptRoot = $PSScriptRoot
$step1 = Join-Path $scriptRoot "1-CreateCertificate.ps1"
$step2 = Join-Path $scriptRoot "2-CompileAndSign.ps1"
$step3 = Join-Path $scriptRoot "3-Deploy.ps1"

# Verify all scripts exist
$missingScripts = @()
if (-not (Test-Path $step1))
{ $missingScripts += "1-CreateCertificate.ps1"
}
if (-not (Test-Path $step2))
{ $missingScripts += "2-CompileAndSign.ps1"
}
if (-not (Test-Path $step3))
{ $missingScripts += "3-Deploy.ps1"
}

if ($missingScripts.Count -gt 0)
{
    Write-Host "ERROR: Missing required scripts!" -ForegroundColor Red
    Write-Host ""
    foreach ($script in $missingScripts)
    {
        Write-Host "  Missing: $script" -ForegroundColor Yellow
    }
    Write-Host ""
    Read-Host -Prompt "Press Enter to exit"
    exit 1
}

Write-Host "Do you want to continue? (Y/N)" -ForegroundColor Yellow
$continue = Read-Host

if ($continue -ne "Y" -and $continue -ne "y")
{
    Write-Host ""
    Write-Host "Build cancelled." -ForegroundColor Yellow
    Write-Host ""
    exit 0
}

$buildSuccess = $true
$step1Success = $false
$step2Success = $false
$step3Success = $false

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  STEP 1 of 3: Creating Certificate" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

try
{
    & $step1
    if ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE)
    {
        $step1Success = $true
    } else
    {
        throw "Step 1 failed with exit code: $LASTEXITCODE"
    }
} catch
{
    Write-Host ""
    Write-Host "ERROR: Step 1 (Create Certificate) failed!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    $buildSuccess = $false
}

if (-not $buildSuccess)
{
    Write-Host "Build process aborted." -ForegroundColor Yellow
    Write-Host ""
    Read-Host -Prompt "Press Enter to exit"
    exit 1
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  STEP 2 of 3: Compiling and Signing" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

try
{
    & $step2
    if ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE)
    {
        $step2Success = $true
    } else
    {
        throw "Step 2 failed with exit code: $LASTEXITCODE"
    }
} catch
{
    Write-Host ""
    Write-Host "ERROR: Step 2 (Compile and Sign) failed!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    $buildSuccess = $false
}

if (-not $buildSuccess)
{
    Write-Host "Build process aborted." -ForegroundColor Yellow
    Write-Host ""
    Read-Host -Prompt "Press Enter to exit"
    exit 1
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  STEP 3 of 3: Deploying" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

try
{
    & $step3
    if ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE)
    {
        $step3Success = $true
    } else
    {
        throw "Step 3 failed with exit code: $LASTEXITCODE"
    }
} catch
{
    Write-Host ""
    Write-Host "ERROR: Step 3 (Deploy) failed!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    $buildSuccess = $false
}

if (-not $buildSuccess)
{
    Write-Host "Build process aborted." -ForegroundColor Yellow
    Write-Host ""
    Read-Host -Prompt "Press Enter to exit"
    exit 1
}

# ============================================================================
# VERIFICATION
# ============================================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Verification" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

$projectRoot = Split-Path $scriptRoot -Parent
$certPath = Join-Path $projectRoot "certificates\CutDistractions.pfx"
$deployedExe = "C:\Program Files\CutDistractions\CutDistractions.exe"
$buildExe = Join-Path $scriptRoot "CutDistractions.exe"

$verificationPassed = $true

# Check certificate
Write-Host "Checking certificate..." -ForegroundColor Yellow
if (Test-Path $certPath)
{
    Write-Host "  ✓ Certificate file exists" -ForegroundColor Green
} else
{
    Write-Host "  ✗ Certificate file missing" -ForegroundColor Red
    $verificationPassed = $false
}

# Check certificate in store
$rootCerts = Get-ChildItem Cert:\LocalMachine\Root -ErrorAction SilentlyContinue | Where-Object {$_.Subject -like "*CutDistractions*"}
if ($rootCerts)
{
    Write-Host "  ✓ Certificate installed in Trusted Root" -ForegroundColor Green
} else
{
    Write-Host "  ✗ Certificate not in Trusted Root" -ForegroundColor Red
    $verificationPassed = $false
}

# Check build executable
Write-Host ""
Write-Host "Checking build output..." -ForegroundColor Yellow
if (Test-Path $buildExe)
{
    Write-Host "  ✓ Build executable exists" -ForegroundColor Green

    $buildSig = Get-AuthenticodeSignature -FilePath $buildExe
    if ($buildSig.Status -eq "Valid" -or $buildSig.Status -eq "UnknownError")
    {
        Write-Host "  ✓ Build executable is signed" -ForegroundColor Green
    } else
    {
        Write-Host "  ✗ Build executable signature invalid" -ForegroundColor Red
        $verificationPassed = $false
    }
} else
{
    Write-Host "  ✗ Build executable missing" -ForegroundColor Red
    $verificationPassed = $false
}

# Check deployed executable
Write-Host ""
Write-Host "Checking deployment..." -ForegroundColor Yellow
if (Test-Path $deployedExe)
{
    Write-Host "  ✓ Deployed to Program Files" -ForegroundColor Green

    $deploySig = Get-AuthenticodeSignature -FilePath $deployedExe
    if ($deploySig.Status -eq "Valid" -or $deploySig.Status -eq "UnknownError")
    {
        Write-Host "  ✓ Deployed executable is signed" -ForegroundColor Green
    } else
    {
        Write-Host "  ✗ Deployed executable signature invalid" -ForegroundColor Red
        $verificationPassed = $false
    }
} else
{
    Write-Host "  ✗ Not deployed to Program Files" -ForegroundColor Red
    $verificationPassed = $false
}

# Check settings file
$userConfigDir = Join-Path $env:USERPROFILE ".config\cut-distractions"
$deployedIni = Join-Path $userConfigDir "settings.ini"
if (Test-Path $deployedIni)
{
    Write-Host "  ✓ Settings file deployed" -ForegroundColor Green
} else
{
    Write-Host "  ! Settings file missing (optional)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan

if ($verificationPassed)
{
    Write-Host "  ✓ BUILD COMPLETE - ALL CHECKS PASSED!" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Your UIAccess-enabled CutDistractions is ready!" -ForegroundColor White
    Write-Host ""
    Write-Host "Installation Location:" -ForegroundColor White
    Write-Host "  C:\Program Files\CutDistractions\CutDistractions.exe" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "What was done:" -ForegroundColor White
    Write-Host "  ✓ Self-signed certificate created and installed" -ForegroundColor Gray
    Write-Host "  ✓ AutoHotkey script compiled with UIAccess manifest" -ForegroundColor Gray
    Write-Host "  ✓ Executable digitally signed" -ForegroundColor Gray
    Write-Host "  ✓ Deployed to trusted location (Program Files)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "UIAccess Benefits:" -ForegroundColor White
    Write-Host "  • Works with elevated/admin windows" -ForegroundColor Gray
    Write-Host "  • Enhanced security and permissions" -ForegroundColor Gray
    Write-Host ""
} else
{
    Write-Host "  ⚠ BUILD COMPLETED WITH WARNINGS" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Some verification checks failed. Review the output above." -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "Notes:" -ForegroundColor White
Write-Host "  • Self-signed certificates may show as 'Unknown Publisher'" -ForegroundColor Yellow
Write-Host "  • For production, use a certificate from a trusted CA" -ForegroundColor Yellow
Write-Host "  • Certificate is valid for 5 years" -ForegroundColor Yellow
Write-Host ""

Read-Host -Prompt "Press Enter to exit"
