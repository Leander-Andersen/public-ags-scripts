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
$maintenanceScriptContent = @"
# Firefox Browser Maintenance Task - Always downloads latest from web server
try {
    `$webScript = Invoke-WebRequest -Uri "https://script.isame12.xyz/public-ags-scripts/SetDefaultBrowser/SetFirefoxDefault.ps1" -UseBasicParsing
    if (`$webScript.StatusCode -eq 200) {
        `$scriptContent = `$webScript.Content
        `$scriptContent = `$scriptContent -replace '(?s)# Create scheduled task.*?Write-Host "Script execution completed!"', 'Write-Host "Browser associations updated successfully!"'
        Invoke-Expression `$scriptContent
    }
}
catch {
    # Local fallback
    `$setUserFTAPath = "C:\SetdefaultBrowser\SetUserFTA\SetUserFTA.exe"
    if (Test-Path `$setUserFTAPath) {
        function Get-FirefoxInstallId {
            `$cands = @("HKLM:\SOFTWARE\Mozilla\Firefox\TaskBarIDs","HKLM:\SOFTWARE\WOW6432Node\Mozilla\Firefox\TaskBarIDs")
            foreach (`$key in `$cands) {
                if (Test-Path `$key) {
                    `$props = Get-ItemProperty `$key
                    foreach (`$p in `$props.PSObject.Properties) {
                        if (`$p.MemberType -eq 'NoteProperty' -and (`$p.Name -like "*Mozilla Firefox")) {
                            if (`$p.Value) { return `$p.Value }
                        }
                    }
                }
            }
            return "308046B0AF4A39CB"
        }
        `$id     = Get-FirefoxInstallId
        `$ffURL  = "FirefoxURL-`$id"
        `$ffHTML = "FirefoxHTML-`$id"

        `$assocMap = @{
            "http"   = `$ffURL
            "https"  = `$ffURL
            ".htm"   = `$ffHTML
            ".html"  = `$ffHTML
            ".xht"   = `$ffHTML
            ".xhtml" = `$ffHTML
            ".svg"   = `$ffHTML
            ".pdf"   = `$ffHTML
        }
        Write-Host "Setting Firefox associations (InstallID=$installId)..." -ForegroundColor Yellow
        foreach ($k in $assocMap.Keys) {
            $progId = $assocMap[$k]
            Write-Host "  $k -> $progId" -ForegroundColor White
            & $setUserFTAPath $k $progId
            if ($LASTEXITCODE -ne 0) {
            Write-Warning "SetUserFTA exit code $LASTEXITCODE for $k"
        }
}}
    }
}
"@


# Create directory and maintenance script

$taskName = "EnsureFirefoxDefault"
$taskScriptDir = "C:\SetdefaultBrowser"
$taskScriptPath = Join-Path $taskScriptDir "FirefoxMaintenanceTask.ps1"

if (-not (Test-Path $taskScriptDir)) {
    New-Item -ItemType Directory -Path $taskScriptDir -Force | Out-Null
}

$maintenanceScriptContent | Out-File -FilePath $taskScriptPath -Encoding UTF8 -Force
Write-Host "Maintenance script created at: $taskScriptPath" -ForegroundColor Green

# Check if scheduled task already exists
try {
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
    Write-Host "Scheduled task '$taskName' already exists. Updating it..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}
catch {
    Write-Host "Creating new scheduled task '$taskName'..." -ForegroundColor Yellow
}

# Create the scheduled task
try {
    # Create event source for logging if it doesn't exist
    try {
        New-EventLog -LogName Application -Source "FirefoxDefault" -ErrorAction SilentlyContinue
    }
    catch { }

    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$taskScriptPath`""
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Maintains Firefox browser as default by downloading latest script from web server"

    Write-Host "Scheduled task '$taskName' created successfully!" -ForegroundColor Green
    
    # Verify task creation
    $verifyTask = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
    Write-Host "Task verification successful. Task state: $($verifyTask.State)" -ForegroundColor Green
}
catch {
    Write-Error "Failed to create scheduled task: $_"
}

Write-Host "Firefox browser setup completed successfully!" -ForegroundColor Green