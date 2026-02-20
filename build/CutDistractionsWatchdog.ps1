# ============================================================================
# CutDistractionsWatchdog.ps1
# Monitors CutDistractions.exe and restarts it if it exits unexpectedly.
#
# The watchdog respects a registry flag written by the app itself:
#   HKCU\Software\CutDistractions\UserExited = 1  → user exited via password, do not restart
#   HKCU\Software\CutDistractions\UserExited = 0  → normal startup / unexpected exit, restart
# ============================================================================

$exePath     = "C:\Program Files\CutDistractions\CutDistractions.exe"
$regPath     = "HKCU:\Software\CutDistractions"
$regValue    = "UserExited"
$checkEvery  = 5   # seconds between checks

while ($true) {
    Start-Sleep -Seconds $checkEvery

    # Read the UserExited flag; treat missing key as 0 (not intentionally exited)
    $userExited = $false
    try {
        $val = Get-ItemPropertyValue -Path $regPath -Name $regValue -ErrorAction Stop
        $userExited = ($val -eq 1)
    } catch {
        $userExited = $false
    }

    if ($userExited) {
        continue
    }

    # If the process is not running, restart it
    $proc = Get-Process -Name "CutDistractions" -ErrorAction SilentlyContinue
    if (-not $proc) {
        if (Test-Path $exePath) {
            Start-Process -FilePath $exePath -WorkingDirectory (Split-Path $exePath)
        }
    }
}
