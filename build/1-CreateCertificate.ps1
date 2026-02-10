# ============================================================================
# 1-CreateCertificate.ps1
# Creates a self-signed code signing certificate for UIAccess
# ============================================================================

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  CutDistractions - Certificate Creation" -ForegroundColor Cyan
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

# Certificate parameters
$certName = "CutDistractions Code Signing"
$certPath = Join-Path $PSScriptRoot "..\certificates"
$pfxPassword = "CutDistractions2024!"

# Create certificates directory if it doesn't exist
if (-not (Test-Path $certPath))
{
    New-Item -ItemType Directory -Path $certPath -Force | Out-Null
}

Write-Host "Creating self-signed code signing certificate..." -ForegroundColor Yellow
Write-Host ""

try
{
    # Create the certificate
    $cert = New-SelfSignedCertificate `
        -Type CodeSigningCert `
        -Subject "CN=$certName" `
        -KeyUsage DigitalSignature `
        -FriendlyName $certName `
        -CertStoreLocation "Cert:\CurrentUser\My" `
        -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3", "2.5.29.19={text}") `
        -KeyExportPolicy Exportable `
        -KeyLength 2048 `
        -KeyAlgorithm RSA `
        -HashAlgorithm SHA256 `
        -NotAfter (Get-Date).AddYears(5)

    Write-Host "✓ Certificate created successfully!" -ForegroundColor Green
    Write-Host "  Thumbprint: $($cert.Thumbprint)" -ForegroundColor Gray
    Write-Host ""

    # Export to PFX file
    $pfxFile = Join-Path $certPath "CutDistractions.pfx"
    $securePassword = ConvertTo-SecureString -String $pfxPassword -Force -AsPlainText

    Export-PfxCertificate -Cert $cert -FilePath $pfxFile -Password $securePassword | Out-Null
    Write-Host "✓ Certificate exported to: $pfxFile" -ForegroundColor Green
    Write-Host "  Password: $pfxPassword" -ForegroundColor Gray
    Write-Host ""

    # Export to CER file (public key only)
    $cerFile = Join-Path $certPath "CutDistractions.cer"
    Export-Certificate -Cert $cert -FilePath $cerFile | Out-Null
    Write-Host "✓ Public certificate exported to: $cerFile" -ForegroundColor Green
    Write-Host ""

    # Install certificate to Trusted Root
    Write-Host "Installing certificate to Trusted Root Certification Authorities..." -ForegroundColor Yellow
    try
    {
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root", "LocalMachine")
        $store.Open("ReadWrite")
        $store.Add($cert)
        $store.Close()
        Write-Host "✓ Certificate installed to Trusted Root!" -ForegroundColor Green
        Write-Host ""
    } catch
    {
        Write-Host "WARNING: Could not install to Trusted Root!" -ForegroundColor Yellow
        Write-Host $_.Exception.Message -ForegroundColor Yellow
        Write-Host "You may need to install manually." -ForegroundColor Yellow
        Write-Host ""
    }

    # Also install to Trusted Publishers for driver signing
    Write-Host "Installing certificate to Trusted Publishers..." -ForegroundColor Yellow
    try
    {
        $publisherStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("TrustedPublisher", "LocalMachine")
        $publisherStore.Open("ReadWrite")
        $publisherStore.Add($cert)
        $publisherStore.Close()
        Write-Host "✓ Certificate installed to Trusted Publishers!" -ForegroundColor Green
        Write-Host ""
    } catch
    {
        Write-Host "WARNING: Could not install to Trusted Publishers!" -ForegroundColor Yellow
        Write-Host $_.Exception.Message -ForegroundColor Yellow
        Write-Host ""
    }

    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "  SUCCESS! Certificate is ready for use" -ForegroundColor Green
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Certificate Details:" -ForegroundColor White
    Write-Host "  Name:       $certName" -ForegroundColor Gray
    Write-Host "  Thumbprint: $($cert.Thumbprint)" -ForegroundColor Gray
    Write-Host "  Valid From: $($cert.NotBefore)" -ForegroundColor Gray
    Write-Host "  Valid To:   $($cert.NotAfter)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor White
    Write-Host "  1. Run '2-CompileAndSign.ps1' to compile and sign the executable" -ForegroundColor Cyan
    Write-Host "  2. Run '3-Deploy.ps1' to deploy to Program Files" -ForegroundColor Cyan
    Write-Host ""

} catch
{
    Write-Host "ERROR: Failed to create certificate!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Read-Host -Prompt "Press Enter to exit"
    exit 1
}

Read-Host -Prompt "Press Enter to continue"
