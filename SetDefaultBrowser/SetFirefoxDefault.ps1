<#
Single-file installer + maintainer:
Run this once elevated. It will copy itself to C:\SetdefaultBrowser\SetFirefoxDefault.ps1,
apply defaults now, and register a scheduled task that re-runs the installed script at each logon.
#>

# Elevation: re-launch as admin if needed
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "This script must be run as Administrator. Re-launching elevated..."
    Start-Process -FilePath powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Definition)`""
    exit
}

$installDir = "C:\SetdefaultBrowser"
$installedScript = Join-Path $installDir "SetFirefoxDefault.ps1"
$taskName = "EnsureFirefoxDefault"
$setUserFTAUrl = "https://script.isame12.xyz/public-ags-scripts/SetDefaultBrowser/SetUserFTA.exe"
$downloadFolder = Join-Path $installDir "SetUserFTA"
$setUserFTAPath = Join-Path $downloadFolder "SetUserFTA.exe"
$logDir = Join-Path $installDir "logs"

# Ensure install dir
New-Item -Path $installDir -ItemType Directory -Force | Out-Null
New-Item -Path $logDir -ItemType Directory -Force | Out-Null
New-Item -Path $downloadFolder -ItemType Directory -Force | Out-Null

function Download-SetUserFTA {
    if (-not (Test-Path $setUserFTAPath)) {
        try {
            Write-Host "Downloading SetUserFTA.exe..."
            Invoke-WebRequest -Uri $setUserFTAUrl -OutFile $setUserFTAPath -UseBasicParsing -TimeoutSec 60
            Write-Host "Downloaded SetUserFTA.exe to $setUserFTAPath"
        } catch {
            Write-Warning "Failed to download SetUserFTA.exe: $_"
            return $false
        }
    } else {
        Write-Host "SetUserFTA.exe already present"
    }
    return (Test-Path $setUserFTAPath)
}

function Get-FirefoxInstallId {
    $cands = @(
        "HKLM:\SOFTWARE\Mozilla\Firefox\TaskBarIDs",
        "HKLM:\SOFTWARE\WOW6432Node\Mozilla\Firefox\TaskBarIDs"
    )
    foreach ($key in $cands) {
        if (Test-Path $key) {
            $props = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
            foreach ($p in $props.PSObject.Properties) {
                if ($p.MemberType -eq 'NoteProperty' -and ($p.Name -like "*Mozilla Firefox")) {
                    if ($p.Value) { return $p.Value }
                }
            }
        }
    }
    return "308046B0AF4A39CB"
}

function Set-Firefox-Associations {
    param(
        [string]$exePath
    )

    if (-not (Test-Path $exePath)) {
        Write-Warning "SetUserFTA not found at $exePath. Aborting association changes."
        return
    }

    $id = Get-FirefoxInstallId
    Write-Host "Firefox InstallID: $id"

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

    foreach ($k in $assocMap.Keys) {
        $progId = $assocMap[$k]
        Write-Host "Setting: $k -> $progId"
        & "$exePath" $k $progId
        $exit = $LASTEXITCODE
        if ($exit -ne 0) {
            Write-Warning "SetUserFTA exit code $exit for $k"
        } else {
            Write-Host "  OK"
        }
    }
}

function Install-Self {
    # Copy this running file to install location so task can run it later
    $src = $MyInvocation.MyCommand.Definition
    if ($src -and (Test-Path $src)) {
        Copy-Item -Path $src -Destination $installedScript -Force
        Write-Host "Installed script to $installedScript"
    } else {
        Write-Warning "Unable to determine script path. Task will reference current file location instead."
    }
}

function Create-Log {
    $log = Join-Path $logDir ("Run-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
    return $log
}

function Register-MaintenanceTask {
    param(
        [string]$scriptToRun
    )

    $pwsh = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
    $arg = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptToRun`""

    $action = New-ScheduledTaskAction -Execute $pwsh -Argument $arg
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $userId = "$($env:USERDOMAIN)\$($env:USERNAME)"
    # RunLevel Highest => elevated on logon without prompting (task created while elevated)
    $principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries

    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    }

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Keep Firefox as default at each user logon"
    Write-Host "Scheduled task '$taskName' registered to run: $scriptToRun"
}

function Unregister-MaintenanceTask {
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "Scheduled task '$taskName' removed."
    } else {
        Write-Host "Scheduled task '$taskName' not found."
    }
}

# --- Main flow ---
# Install self to install dir
Install-Self

# Download SetUserFTA and apply associations now
$logFile = Create-Log
Start-Transcript -Path $logFile -Force
try {
    $haveTool = Download-SetUserFTA
    if ($haveTool) {
        Set-Firefox-Associations -exePath $setUserFTAPath
    } else {
        Write-Warning "Could not obtain SetUserFTA; associations not changed."
    }

    # Register scheduled task to re-run this installed script at each user logon
    $scriptForTask = if (Test-Path $installedScript) { $installedScript } else { $MyInvocation.MyCommand.Definition }
    Register-MaintenanceTask -scriptToRun $scriptForTask

    Write-Host "Done. Logs: $logDir"
    Write-Host "To stop automatic enforcement run (once elevated):"
    Write-Host "  Unregister-ScheduledTask -TaskName $taskName -Confirm:\$false"
    Write-Host "  (and optionally remove $installDir)"
}
catch {
    Write-Error "Error during run: $_"
}
finally {
    Stop-Transcript
}
```// filepath: d:\OneDrive - Vestfold fylkeskommune\Documents\GithubDesktopRepos\public-ags-scripts\SetDefaultBrowser\SetFirefoxDefault.ps1
<#
Single-file installer + maintainer:
Run this once elevated. It will copy itself to C:\SetdefaultBrowser\SetFirefoxDefault.ps1,
apply defaults now, and register a scheduled task that re-runs the installed script at each logon.
#>

# Elevation: re-launch as admin if needed
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "This script must be run as Administrator. Re-launching elevated..."
    Start-Process -FilePath powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Definition)`""
    exit
}

$installDir = "C:\SetdefaultBrowser"
$installedScript = Join-Path $installDir "SetFirefoxDefault.ps1"
$taskName = "EnsureFirefoxDefault"
$setUserFTAUrl = "https://script.isame12.xyz/public-ags-scripts/SetDefaultBrowser/SetUserFTA.exe"
$downloadFolder = Join-Path $installDir "SetUserFTA"
$setUserFTAPath = Join-Path $downloadFolder "SetUserFTA.exe"
$logDir = Join-Path $installDir "logs"

# Ensure install dir
New-Item -Path $installDir -ItemType Directory -Force | Out-Null
New-Item -Path $logDir -ItemType Directory -Force | Out-Null
New-Item -Path $downloadFolder -ItemType Directory -Force | Out-Null

function Download-SetUserFTA {
    if (-not (Test-Path $setUserFTAPath)) {
        try {
            Write-Host "Downloading SetUserFTA.exe..."
            Invoke-WebRequest -Uri $setUserFTAUrl -OutFile $setUserFTAPath -UseBasicParsing -TimeoutSec 60
            Write-Host "Downloaded SetUserFTA.exe to $setUserFTAPath"
        } catch {
            Write-Warning "Failed to download SetUserFTA.exe: $_"
            return $false
        }
    } else {
        Write-Host "SetUserFTA.exe already present"
    }
    return (Test-Path $setUserFTAPath)
}

function Get-FirefoxInstallId {
    $cands = @(
        "HKLM:\SOFTWARE\Mozilla\Firefox\TaskBarIDs",
        "HKLM:\SOFTWARE\WOW6432Node\Mozilla\Firefox\TaskBarIDs"
    )
    foreach ($key in $cands) {
        if (Test-Path $key) {
            $props = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
            foreach ($p in $props.PSObject.Properties) {
                if ($p.MemberType -eq 'NoteProperty' -and ($p.Name -like "*Mozilla Firefox")) {
                    if ($p.Value) { return $p.Value }
                }
            }
        }
    }
    return "308046B0AF4A39CB"
}

function Set-Firefox-Associations {
    param(
        [string]$exePath
    )

    if (-not (Test-Path $exePath)) {
        Write-Warning "SetUserFTA not found at $exePath. Aborting association changes."
        return
    }

    $id = Get-FirefoxInstallId
    Write-Host "Firefox InstallID: $id"

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

    foreach ($k in $assocMap.Keys) {
        $progId = $assocMap[$k]
        Write-Host "Setting: $k -> $progId"
        & "$exePath" $k $progId
        $exit = $LASTEXITCODE
        if ($exit -ne 0) {
            Write-Warning "SetUserFTA exit code $exit for $k"
        } else {
            Write-Host "  OK"
        }
    }
}

function Install-Self {
    # Copy this running file to install location so task can run it later
    $src = $MyInvocation.MyCommand.Definition
    if ($src -and (Test-Path $src)) {
        Copy-Item -Path $src -Destination $installedScript -Force
        Write-Host "Installed script to $installedScript"
    } else {
        Write-Warning "Unable to determine script path. Task will reference current file location instead."
    }
}

function Create-Log {
    $log = Join-Path $logDir ("Run-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
    return $log
}

function Register-MaintenanceTask {
    param(
        [string]$scriptToRun
    )

    $pwsh = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
    $arg = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptToRun`""

    $action = New-ScheduledTaskAction -Execute $pwsh -Argument $arg
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $userId = "$($env:USERDOMAIN)\$($env:USERNAME)"
    # RunLevel Highest => elevated on logon without prompting (task created while elevated)
    $principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries

    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    }

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Keep Firefox as default at each user logon"
    Write-Host "Scheduled task '$taskName' registered to run: $scriptToRun"
}

function Unregister-MaintenanceTask {
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "Scheduled task '$taskName' removed."
    } else {
        Write-Host "Scheduled task '$taskName' not found."
    }
}

# --- Main flow ---
# Install self to install dir
Install-Self

# Download SetUserFTA and apply associations now
$logFile = Create-Log
Start-Transcript -Path $logFile -Force
try {
    $haveTool = Download-SetUserFTA
    if ($haveTool) {
        Set-Firefox-Associations -exePath $setUserFTAPath
    } else {
        Write-Warning "Could not obtain SetUserFTA; associations not changed."
    }

    # Register scheduled task to re-run this installed script at each user logon
    $scriptForTask = if (Test-Path $installedScript) { $installedScript } else { $MyInvocation.MyCommand.Definition }
    Register-MaintenanceTask -scriptToRun $scriptForTask

    Write-Host "Done. Logs: $logDir"
    Write-Host "To stop automatic enforcement run (once elevated):"
    Write-Host "  Unregister-ScheduledTask -TaskName $taskName -Confirm:\$false"
    Write-Host "  (and optionally remove $installDir)"
}
catch {
    Write-Error "Error during run: $_"
}
finally {
    Stop-Transcript
}