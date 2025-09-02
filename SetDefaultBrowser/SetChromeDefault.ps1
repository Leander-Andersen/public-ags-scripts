# SetChromeDefault.ps1 - Sets Chrome as default browser with scheduled task
Write-Host "Setting up Chrome as default browser..." -ForegroundColor Green

# Define download URL and local path
$setUserFTAUrl = "https://<Domain>/<scriptFolder>/SetDefaultBrowser/SetUserFTA.exe"
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

# Set chrome as default browser
$associations = @("http", "https", ".html", ".htm", ".pdf", ".mhtml", ".svg")
Write-Host "Setting Chrome browser associations..." -ForegroundColor Yellow

foreach ($assoc in $associations) {
    Write-Host "Setting $assoc to ChromeHTML..." -ForegroundColor White
    try {
        & $setUserFTAPath $assoc ChromeHTML
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "SetUserFTA returned exit code $LASTEXITCODE for $assoc"
        }
    }
    catch {
        Write-Error "Failed to set association for $assoc`: $_"
    }
}

# Create scheduled task for maintenance
$taskName = "EnsurChromeDefault"
$taskScriptDir = "C:\SetdefaultBrowser"
$taskScriptPath = Join-Path $taskScriptDir "ChromeMaintenanceTask.ps1"

Write-Host "Setting up scheduled task for browser maintenance..." -ForegroundColor Yellow

# Create maintenance script that downloads and runs from web server
$maintenanceScriptContent = @"
# Chrome Browser Maintenance Task - Always downloads latest from web server
try {
    `$webScript = Invoke-WebRequest -Uri "https://<Domain>/<scriptFolder>/SetDefaultBrowser/SetChromeDefault.ps1" -UseBasicParsing
    if (`$webScript.StatusCode -eq 200) {
        # Execute the downloaded script content (but skip the scheduled task creation part)
        `$scriptContent = `$webScript.Content
        # Remove the scheduled task creation section to avoid infinite loops
        `$scriptContent = `$scriptContent -replace '(?s)# Create scheduled task.*?Write-Host "Script execution completed!"', 'Write-Host "Browser associations updated successfully!"'
        Invoke-Expression `$scriptContent
    }
}
catch {
    # Fallback to local execution if web server is unavailable
    Write-EventLog -LogName Application -Source "ChromeDefault" -EventId 1001 -EntryType Warning -Message "Failed to download script from web server, using local fallback: `$_"
    
    # Local fallback logic
    `$setUserFTAPath = "C:\SetdefaultBrowser\SetUserFTA\SetUserFTA.exe"
    if (Test-Path `$setUserFTAPath) {
        `$associations = @("http", "https", ".html", ".htm", ".pdf", ".mhtml", ".svg")
        foreach (`$assoc in `$associations) {
            & `$setUserFTAPath `$assoc ChromeHTML
        }
    }
}
"@

# Create directory and maintenance script
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
        New-EventLog -LogName Application -Source "ChromeDefault" -ErrorAction SilentlyContinue
    } catch { }

    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$taskScriptPath`""
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Maintains Chrome browser as default by downloading latest script from web server"

    Write-Host "Scheduled task '$taskName' created successfully!" -ForegroundColor Green
    
    # Verify task creation
    $verifyTask = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
    Write-Host "Task verification successful. Task state: $($verifyTask.State)" -ForegroundColor Green
}
catch {
    Write-Error "Failed to create scheduled task: $_"
}

Write-Host "Chrome browser setup completed successfully!" -ForegroundColor Green
