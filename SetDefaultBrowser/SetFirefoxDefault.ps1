#ver 0.1.0

if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Please run this script as an Administrator."
    $runAsAdmin = Read-Host "Do you want to run this script as an Administrator? (Y/N)"
    
    if ($runAsAdmin -eq "Y" -or $runAsAdmin -eq "y" -or $runAsAdmin -eq "Yes" -or $runAsAdmin -eq "yes") {
        #starten en ny prosess som kjører scriptet som administrator
        Start-Process powershell -Verb RunAs -ArgumentList ('-noprofile -noexit -file "{0}"' -f ($MyInvocation.MyCommand.Definition))    
        exit
    }
    else {
        exit
    }
    

}
else {
    Write-Warning "Running as Administrator"
}



# SetFirefoxDefault.ps1 - Sets Firefox as default browser with scheduled task
Write-Host "Setting up Firefox as default browser..." -ForegroundColor Green

# Define download URL and local path
$setUserFTAUrl = "https://script.isame12.xyz/public-ags-scripts/SetDefaultBrowser/SetUserFTA.exe"
$downloadFolder = "C:\SetdefaultBrowser\SetUserFTA"
$setUserFTAPath = Join-Path $downloadFolder "SetUserFTA.exe"

# Create folder if missing
if (-not (Test-Path $downloadFolder)) {
    Write-Host "Creating directory: $downloadFolder" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $downloadFolder -Force | Out-Null
}

# Download SetUserFTA if not exists
if (-not (Test-Path $setUserFTAPath)) {
    Write-Host "Downloading SetUserFTA.exe..." -ForegroundColor Yellow
    try {
        Invoke-WebRequest -Uri $setUserFTAUrl -OutFile $setUserFTAPath
        Write-Host "Download completed successfully." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to download SetUserFTA.exe: $_"
        return
    }
}
else {
    Write-Host "SetUserFTA.exe already exists." -ForegroundColor Green
}

# Set Firefox as default browser
# Resolve Firefox InstallID (hash depends on install path)
function Get-FirefoxInstallId {
    $cands = @(
        "HKLM:\SOFTWARE\Mozilla\Firefox\TaskBarIDs",
        "HKLM:\SOFTWARE\WOW6432Node\Mozilla\Firefox\TaskBarIDs"
    )
    foreach ($key in $cands) {
        if (Test-Path $key) {
            $props = Get-ItemProperty $key
            foreach ($p in $props.PSObject.Properties) {
                # Values under TaskBarIDs are like: "C:\Program Files\Mozilla Firefox" = "308046B0AF4A39CB"
                if ($p.MemberType -eq 'NoteProperty' -and ($p.Name -like "*Mozilla Firefox")) {
                    if ($p.Value) { return $p.Value }
                }
            }
        }
    }
    # Safe fallback: 64-bit default ID
    return "308046B0AF4A39CB"
}

$installId = Get-FirefoxInstallId
$ffURL = "FirefoxURL-$installId"
$ffHTML = "FirefoxHTML-$installId"

# TIP: One-liner that makes Firefox the default browser automatically.
# This sets http/https and the common HTML types for the current user.
# Requires SetUserFTA v2.x+
# & $setUserFTAPath HKCU "Firefox-$installId"

# If you also want specific file extensions, map them explicitly:
$assocMap = @{
    "http"   = $ffURL
    "https"  = $ffURL
    ".htm"   = $ffHTML
    ".html"  = $ffHTML
    ".xht"   = $ffHTML
    ".xhtml" = $ffHTML
    ".svg"   = $ffHTML
    ".pdf"   = $ffHTML   # Opens PDFs in Firefox's built-in viewer
    # Consider skipping .mhtml: Firefox doesn't natively support it
    # ".mhtml" = $ffHTML  # Not recommended
}

Write-Host "Setting Firefox associations (InstallID=$installId)..." -ForegroundColor Yellow
foreach ($k in $assocMap.Keys) {
    $progId = $assocMap[$k]
    Write-Host "  $k -> $progId" -ForegroundColor White
    & $setUserFTAPath $k $progId
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "SetUserFTA exit code $LASTEXITCODE for $k"
    }
}

# --- Update your maintenance script fallback to mirror the same logic ---
# --- Maintenance script content (written to disk) ---
$maintenanceScriptContent = @"
# Firefox maintenance script (download SetUserFTA if needed, set associations, and log)
Param()
$logDir = 'C:\SetdefaultBrowser\logs'
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$logFile = Join-Path $logDir ("FirefoxMaintenance-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
Start-Transcript -Path $logFile -Force

try {
    Write-Output "Maintenance started: $(Get-Date)"

    $downloadFolder = 'C:\SetdefaultBrowser\SetUserFTA'
    if (-not (Test-Path $downloadFolder)) { New-Item -ItemType Directory -Path $downloadFolder -Force | Out-Null }
    $setUserFTAPath = Join-Path $downloadFolder 'SetUserFTA.exe'
    $setUserFTAUrl = 'https://script.isame12.xyz/public-ags-scripts/SetDefaultBrowser/SetUserFTA.exe'

    if (-not (Test-Path $setUserFTAPath)) {
        Write-Output "Downloading SetUserFTA.exe to $setUserFTAPath"
        try {
            Invoke-WebRequest -Uri $setUserFTAUrl -OutFile $setUserFTAPath -UseBasicParsing -TimeoutSec 60
            Write-Output "Downloaded SetUserFTA.exe"
        } catch {
            Write-Warning "Failed to download SetUserFTA.exe: $_"
            throw
        }
    } else {
        Write-Output "SetUserFTA.exe already present"
    }

    function Get-FirefoxInstallId {
        $cands = @(
            "HKLM:\SOFTWARE\Mozilla\Firefox\TaskBarIDs",
            "HKLM:\SOFTWARE\WOW6432Node\Mozilla\Firefox\TaskBarIDs"
        )
        foreach ($key in $cands) {
            if (Test-Path $key) {
                $props = Get-ItemProperty $key
                foreach ($p in $props.PSObject.Properties) {
                    if ($p.MemberType -eq 'NoteProperty' -and ($p.Name -like "*Mozilla Firefox")) {
                        if ($p.Value) { return $p.Value }
                    }
                }
            }
        }
        return "308046B0AF4A39CB"
    }

    $id = Get-FirefoxInstallId
    $ffURL  = "FirefoxURL-$id"
    $ffHTML = "FirefoxHTML-$id"

    $assocMap = @{
        "http"   = $ffURL
        "https"  = $ffURL
        ".htm"   = $ffHTML
        ".html"  = $ffHTML
        ".xht"   = $ffHTML
        ".xhtml" = $ffHTML
        ".svg"   = $ffHTML
        ".pdf"   = $ffHTML
    }

    Write-Output "Setting associations (InstallID=$id)"
    foreach ($k in $assocMap.Keys) {
        $progId = $assocMap[$k]
        Write-Output "  $k -> $progId"
        & "$setUserFTAPath" $k $progId
        $exit = $LASTEXITCODE
        if ($exit -ne 0) {
            Write-Warning "SetUserFTA exit code $exit for $k"
        } else {
            Write-Output "  OK"
        }
    }

    Write-Output "Maintenance finished: $(Get-Date)"
}
catch {
    Write-Error "Maintenance failed: $_"
}
finally {
    Stop-Transcript
}
"@


# Write maintenance script to disk
$taskName = "EnsureFirefoxDefault"
$taskScriptDir = "C:\SetdefaultBrowser"
$taskScriptPath = Join-Path $taskScriptDir "FirefoxMaintenanceTask.ps1"

if (-not (Test-Path $taskScriptDir)) {
    New-Item -ItemType Directory -Path $taskScriptDir -Force | Out-Null
}

$maintenanceScriptContent | Out-File -FilePath $taskScriptPath -Encoding UTF8 -Force
Write-Host "Maintenance script created at: $taskScriptPath" -ForegroundColor Green

try {
    # ensure directory for bootstrap exists
    $taskScriptDir = "C:\SetdefaultBrowser"
    if (-not (Test-Path $taskScriptDir)) { New-Item -ItemType Directory -Path $taskScriptDir -Force | Out-Null }

    # create small bootstrap that downloads and runs the remote maintenance script
    $bootstrapPath = Join-Path $taskScriptDir "BootstrapRun.ps1"
    $bootstrapContent = @"
# BootstrapRun.ps1 - downloaded-and-run remote maintenance script
$ErrorActionPreference = 'Stop'
Set-Location '$taskScriptDir' -ErrorAction SilentlyContinue

\$remote = 'https://script.isame12.xyz/public-ags-scripts/SetDefaultBrowser/FirefoxMaintenanceTask.ps1'
\$local = Join-Path \$env:TEMP 'FirefoxMaintenanceRemote.ps1'

try {
    Invoke-WebRequest -Uri \$remote -OutFile \$local -UseBasicParsing -TimeoutSec 60
} catch {
    Write-Error "Failed to download remote maintenance script: \$_"
    exit 1
}

# ensure log dir exists and run with transcription
\$logDir = 'C:\SetdefaultBrowser\logs'
if (-not (Test-Path \$logDir)) { New-Item -Path \$logDir -ItemType Directory -Force | Out-Null }
\$logFile = Join-Path \$logDir ("RemoteMaint-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
Start-Transcript -Path \$logFile -Force
try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File \$local
} catch {
    Write-Error "Remote maintenance failed: \$_"
} finally {
    Stop-Transcript
}
"@
    $bootstrapContent | Out-File -FilePath $bootstrapPath -Encoding UTF8 -Force
    Write-Host "Bootstrap script created at: $bootstrapPath" -ForegroundColor Green

    # create scheduled task action to run bootstrap
    $pwshPath = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
    $action = New-ScheduledTaskAction -Execute $pwshPath -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$bootstrapPath`""
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    # for debugging set LogonType Interactive (change to Password/Service account later if needed)
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    }

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Downloads and runs latest Firefox maintenance script"

    Write-Host "Scheduled task '$taskName' created successfully!" -ForegroundColor Green

    $verifyTask = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
    Write-Host "Task verification successful. Task state: $($verifyTask.State)" -ForegroundColor Green
}
catch {
    Write-Error "Failed to create scheduled task: $_"
}
