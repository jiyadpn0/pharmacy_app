# Automated Virtual PC Deploy Script
# Silently updates files in J:\draft\PharmaPro_v2.9.3_Update without spawning extra duplicate windows.

$ReleaseDir = "build\windows\x64\runner\Release"
$VirtualDir = "J:\draft\PharmaPro_v2.9.3_Update"

Stop-Process -Name "pharmacy_app" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

if (Test-Path -Path $ReleaseDir) {
    Copy-Item -Path "$ReleaseDir\*" -Destination $VirtualDir -Recurse -Force
    Write-Host "Virtual PC files updated successfully at $VirtualDir" -ForegroundColor Green
} else {
    Write-Host "Release directory not found. Please run 'flutter build windows' first." -ForegroundColor Red
}
