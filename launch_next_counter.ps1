# Dynamic Multi-Counter Auto-Scaler Launcher
# Counts running instances of pharmacy_app and auto-launches the next sequential counter (POS-02, POS-03, POS-04...)

$VirtualDir = "J:\draft\PharmaPro_v2.9.3_Update"
$ExePath = "$VirtualDir\pharmacy_app.exe"

if (-not (Test-Path -Path $ExePath)) {
    Write-Host "Virtual app executable not found at $ExePath" -ForegroundColor Red
    exit 1
}

$runningCount = (Get-Process -Name 'pharmacy_app' -ErrorAction SilentlyContinue).Count
$nextNum = [math]::Max(2, $runningCount + 1)
$numFormatted = if ($nextNum -lt 10) { "0$nextNum" } else { "$nextNum" }
$nextTerminal = "POS-$numFormatted"

Write-Host "Currently running instances: $runningCount" -ForegroundColor Cyan
Write-Host "Auto-scaling next virtual counter: $nextTerminal" -ForegroundColor Green

Start-Process -FilePath $ExePath -ArgumentList "--terminal=$nextTerminal"

Write-Host "Counter $nextTerminal launched successfully!" -ForegroundColor Green
