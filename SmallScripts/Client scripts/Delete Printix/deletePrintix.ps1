#This script deletes the Printix application from a Windows machine

# === Start logging ===
$timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
$logPath = "C:\Windows\Temp\scriptlog-$timestamp.txt"

Start-Transcript -Path $logPath -Force
Write-Host "Logging to: $logPath"

#Check if Printix is installed
$possiblePaths = @(
    "C:\Program Files\Printix.net\Printix Client",
    "C:\Program Files\printix.net\Printix Client",
    "C:\Program Files (x86)\Printix.net\Printix Client"
)

# Try to find a real existing path
$printixPath = $possiblePaths | Where-Object { Test-Path $_ } | Select-Object -First 1


if (Test-Path $printixPath) {
    Write-Host "Printix is installed. Proceeding with uninstallation..."
    #Stop Printix services
    Get-Service -Name "PrintixClient" -ErrorAction SilentlyContinue | Stop-Service -Force
    Get-Service -Name "PrintixUpdater" -ErrorAction SilentlyContinue | Stop-Service

    #Run uninstaller in printix directory unins000.exe

    $uninstallerPath = Join-Path $printixPath "unins000.exe"

    if (Test-Path $uninstallerPath) {
        Write-Host "Running Printix uninstaller..."
        Start-Process -FilePath $uninstallerPath -ArgumentList "/SILENT" -Wait
        Write-Host "Printix uninstallation completed."
    } else {
        Write-Host "Uninstaller not found. Please uninstall Printix manually."
    }
} else {
    Write-Host "Printix is not installed on this machine."
}

# === End logging ===
Stop-Transcript
Write-Host "Log saved to: $logPath"

#Made by Leander Andersen