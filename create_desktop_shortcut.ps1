$DesktopPath = [System.Environment]::GetFolderPath('Desktop')
$ShortcutPath = Join-Path $DesktopPath "PHARMA PRO - Launch Virtual Counter.lnk"
$WScriptShell = New-Object -ComObject WScript.Shell
$Shortcut = $WScriptShell.CreateShortcut($ShortcutPath)
$Shortcut.TargetPath = "J:\android studio\android studio c folder\pharmacy_app\start_dual_counters.bat"
$Shortcut.WorkingDirectory = "J:\android studio\android studio c folder\pharmacy_app"
$Shortcut.Description = "Auto-scale and launch next virtual counter (POS-02, POS-03, POS-04...)"
$Shortcut.Save()
Write-Host "Desktop Shortcut Created Successfully at: $ShortcutPath" -ForegroundColor Green
