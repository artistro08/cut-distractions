# ============================================================================
# 2-CompileAndSign.ps1
# Compiles the AutoHotkey script with UIAccess manifest and signs it
# ============================================================================

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  CutDistractions - Compile and Sign" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# Check if running as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    Write-Host "ERROR: This script must be run as Administrator!" -ForegroundColor Red
    Write-Host "Right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
    Read-Host -Prompt "Press Enter to exit"
    exit 1
}

# Paths
$scriptRoot = $PSScriptRoot
$projectRoot = Split-Path $scriptRoot -Parent
$ahkScript = Join-Path $projectRoot "CutDistractions.ahk"
$manifest = Join-Path $scriptRoot "CutDistractions.manifest"
$outputExe = Join-Path $scriptRoot "CutDistractions.exe"
$iconFile = Join-Path $projectRoot "CutDistractions.ico"
$certPath = Join-Path $projectRoot "certificates\CutDistractions.pfx"
$pfxPassword = "CutDistractions2024!"

# Check if source files exist
if (-not (Test-Path $ahkScript))
{
    Write-Host "ERROR: CutDistractions.ahk not found!" -ForegroundColor Red
    Write-Host "Expected: $ahkScript" -ForegroundColor Yellow
    Read-Host -Prompt "Press Enter to exit"
    exit 1
}

if (-not (Test-Path $manifest))
{
    Write-Host "ERROR: Manifest file not found!" -ForegroundColor Red
    Write-Host "Expected: $manifest" -ForegroundColor Yellow
    Read-Host -Prompt "Press Enter to exit"
    exit 1
}

if (-not (Test-Path $certPath))
{
    Write-Host "ERROR: Certificate not found!" -ForegroundColor Red
    Write-Host "Please run '1-CreateCertificate.ps1' first!" -ForegroundColor Yellow
    Read-Host -Prompt "Press Enter to exit"
    exit 1
}

# Find AutoHotkey compiler
Write-Host "Looking for AutoHotkey v2 compiler..." -ForegroundColor Yellow

$ahkCompilerPaths = @(
    "$env:ProgramFiles\AutoHotkey\Compiler\Ahk2Exe.exe",
    "${env:ProgramFiles(x86)}\AutoHotkey\Compiler\Ahk2Exe.exe",
    "$env:LOCALAPPDATA\Programs\AutoHotkey\Compiler\Ahk2Exe.exe"
)

$ahkCompiler = $null
foreach ($path in $ahkCompilerPaths)
{
    if (Test-Path $path)
    {
        $ahkCompiler = $path
        break
    }
}

if (-not $ahkCompiler)
{
    Write-Host "ERROR: AutoHotkey compiler (Ahk2Exe.exe) not found!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please install AutoHotkey v2 from:" -ForegroundColor Yellow
    Write-Host "  https://www.autohotkey.com/" -ForegroundColor Cyan
    Write-Host ""
    Read-Host -Prompt "Press Enter to exit"
    exit 1
}

Write-Host "✓ Found: $ahkCompiler" -ForegroundColor Green
Write-Host ""

# Remove old output if exists
if (Test-Path $outputExe)
{
    Write-Host "Removing old executable..." -ForegroundColor Yellow
    Remove-Item $outputExe -Force
}

# Compile the script
Write-Host "Compiling AutoHotkey script..." -ForegroundColor Yellow
Write-Host "  Source: $ahkScript" -ForegroundColor Gray
Write-Host "  Output: $outputExe" -ForegroundColor Gray
Write-Host ""

$compileArgs = @(
    "/in", "`"$ahkScript`"",
    "/out", "`"$outputExe`""
)

if (Test-Path $iconFile)
{
    $compileArgs += "/icon", "`"$iconFile`""
    Write-Host "  Icon: $iconFile" -ForegroundColor Gray
}

try
{
    $process = Start-Process -FilePath $ahkCompiler -ArgumentList $compileArgs -Wait -PassThru -NoNewWindow

    if ($process.ExitCode -ne 0)
    {
        throw "Compiler returned exit code: $($process.ExitCode)"
    }

    if (-not (Test-Path $outputExe))
    {
        throw "Output executable was not created"
    }

    Write-Host "✓ Compilation successful!" -ForegroundColor Green
    Write-Host ""
} catch
{
    Write-Host "ERROR: Compilation failed!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Read-Host -Prompt "Press Enter to exit"
    exit 1
}

# Embed the manifest using mt.exe
Write-Host "Embedding UIAccess manifest..." -ForegroundColor Yellow

# Find mt.exe (Windows SDK)
$mtPaths = @(
    "C:\Program Files (x86)\Windows Kits\10\bin\*\x64\mt.exe",
    "C:\Program Files (x86)\Windows Kits\10\bin\*\x86\mt.exe",
    "C:\Program Files\Windows Kits\10\bin\*\x64\mt.exe",
    "C:\Program Files\Windows Kits\10\bin\*\x86\mt.exe"
)

$mtExe = $null
foreach ($pattern in $mtPaths)
{
    $found = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found)
    {
        $mtExe = $found.FullName
        break
    }
}

if (-not $mtExe)
{
    Write-Host "WARNING: mt.exe not found! Trying alternative method..." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Note: For production use, install Windows SDK from:" -ForegroundColor Yellow
    Write-Host "  https://developer.microsoft.com/windows/downloads/windows-sdk/" -ForegroundColor Cyan
    Write-Host ""

    # Alternative: Use Resource Hacker if available
    $resourceHacker = "C:\Program Files (x86)\Resource Hacker\ResourceHacker.exe"
    if (Test-Path $resourceHacker)
    {
        Write-Host "Using Resource Hacker as alternative..." -ForegroundColor Yellow

        $rhScript = Join-Path $scriptRoot "temp_rh_script.txt"
        "[FILENAMES]`nExe=$outputExe`nSaveAs=$outputExe`n[COMMANDS]`n-delete MANIFEST,1,`n-add `"$manifest`", MANIFEST,1," | Out-File -FilePath $rhScript -Encoding ASCII

        Start-Process -FilePath $resourceHacker -ArgumentList "-script `"$rhScript`"" -Wait -NoNewWindow
        Remove-Item $rhScript -Force -ErrorAction SilentlyContinue

        Write-Host "✓ Manifest embedded with Resource Hacker!" -ForegroundColor Green
    } else
    {
        Write-Host "ERROR: Neither mt.exe nor Resource Hacker found!" -ForegroundColor Red
        Write-Host "The executable was compiled but the manifest could not be embedded." -ForegroundColor Yellow
        Write-Host "You need to install either:" -ForegroundColor Yellow
        Write-Host "  1. Windows SDK (contains mt.exe)" -ForegroundColor Cyan
        Write-Host "  2. Resource Hacker (http://www.angusj.com/resourcehacker/)" -ForegroundColor Cyan
        Read-Host -Prompt "Press Enter to exit"
        exit 1
    }
} else
{
    Write-Host "✓ Found: $mtExe" -ForegroundColor Green

    try
    {
        $mtArgs = @(
            "-manifest", "`"$manifest`"",
            "-outputresource:`"$outputExe`";#1"
        )

        $mtProcess = Start-Process -FilePath $mtExe -ArgumentList $mtArgs -Wait -PassThru -NoNewWindow

        if ($mtProcess.ExitCode -ne 0)
        {
            throw "mt.exe returned exit code: $($mtProcess.ExitCode)"
        }

        Write-Host "✓ Manifest embedded successfully!" -ForegroundColor Green
        Write-Host ""
    } catch
    {
        Write-Host "ERROR: Failed to embed manifest!" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        Read-Host -Prompt "Press Enter to exit"
        exit 1
    }
}

# Sign the executable
Write-Host "Signing executable with certificate..." -ForegroundColor Yellow

try
{
    $securePassword = ConvertTo-SecureString -String $pfxPassword -Force -AsPlainText

    # Use Set-AuthenticodeSignature
    $signResult = Set-AuthenticodeSignature -FilePath $outputExe -Certificate (Get-PfxCertificate -FilePath $certPath -Password $securePassword) -TimestampServer "http://timestamp.digicert.com"

    if ($signResult.Status -ne "Valid")
    {
        throw "Signing failed with status: $($signResult.Status)"
    }

    Write-Host "✓ Executable signed successfully!" -ForegroundColor Green
    Write-Host ""
} catch
{
    Write-Host "ERROR: Failed to sign executable!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Read-Host -Prompt "Press Enter to exit"
    exit 1
}

# Verify the signature
Write-Host "Verifying signature..." -ForegroundColor Yellow
$signature = Get-AuthenticodeSignature -FilePath $outputExe

if ($signature.Status -eq "Valid")
{
    Write-Host "✓ Signature is valid!" -ForegroundColor Green
} else
{
    Write-Host "WARNING: Signature status is '$($signature.Status)'" -ForegroundColor Yellow
    Write-Host "This is expected for self-signed certificates." -ForegroundColor Gray
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  SUCCESS! Executable compiled and signed" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Output: $outputExe" -ForegroundColor White
Write-Host ""
Write-Host "File Information:" -ForegroundColor White
$fileInfo = Get-Item $outputExe
Write-Host "  Size: $([math]::Round($fileInfo.Length / 1KB, 2)) KB" -ForegroundColor Gray
Write-Host "  Modified: $($fileInfo.LastWriteTime)" -ForegroundColor Gray
Write-Host ""
Write-Host "Signature Information:" -ForegroundColor White
Write-Host "  Status: $($signature.Status)" -ForegroundColor Gray
Write-Host "  Signer: $($signature.SignerCertificate.Subject)" -ForegroundColor Gray
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor White
Write-Host "  1. Run '3-Deploy.ps1' to deploy to Program Files" -ForegroundColor Cyan
Write-Host "  2. Or manually copy to: C:\Program Files\CutDistractions\" -ForegroundColor Cyan
Write-Host ""

Read-Host -Prompt "Press Enter to continue"
