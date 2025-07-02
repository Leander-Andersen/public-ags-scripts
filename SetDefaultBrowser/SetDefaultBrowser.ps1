# Ensure script runs as administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Please run this script as an Administrator."
    $runAsAdmin = Read-Host "Do you want to run this script as an Administrator? (Y/N)"
    
    if ($runAsAdmin -eq "Y" -or $runAsAdmin -eq "y" -or $runAsAdmin -eq "Yes" -or $runAsAdmin -eq "yes") {
        # Start a new process running the script as administrator
        Start-Process powershell -Verb RunAs -ArgumentList ('-noprofile -noexit -file "{0}"' -f ($MyInvocation.MyCommand.Definition))
        exit
    }
    else {
        exit
    }
}
else {
    Write-Host "Running as Administrator" -ForegroundColor Green
}

Write-Host "What browser do you want as default?" -ForegroundColor Cyan
Write-Host "(1) Brave" -ForegroundColor White
Write-Host "(2) Chrome" -ForegroundColor White  
Write-Host "(3) Firefox" -ForegroundColor White
$DefaultBrowser = Read-Host "Enter your choice"

# Define your web server URLs - UPDATE THESE TO YOUR ACTUAL URLS

$braveScriptUrl = "http://script.isame12.xyz/public-ags-scripts/SetDefaultBrowser/SetBraveDefault.ps1"
$chromeScriptUrl = "http://script.isame12.xyz/public-ags-scripts/SetDefaultBrowser/SetChromeDefault.ps1"
$firefoxScriptUrl = "http://script.isame12.xyz/public-ags-scripts/SetDefaultBrowser/SetFirefoxDefault.ps1"


# Run the appropriate script based on user selection
if ($DefaultBrowser -eq "1") {
    Write-Host "Downloading and running Brave default script..." -ForegroundColor Yellow
    try {
        $scriptContent = [System.Text.Encoding]::UTF8.GetString(
    (Invoke-WebRequest -UseBasicParsing -Uri $braveScriptUrl).Content
    )
    Invoke-Expression $scriptContent
    }
    catch {
        Write-Error "Failed to download or execute Brave script: $_ go die"
        Write-Host "you go to hell and go down" -ForegroundColor Red
    }
}

elseif ($DefaultBrowser -eq "2") {
    Write-Host "Downloading and running Chrome default script..." -ForegroundColor Yellow
    try {
        $scriptContent = [System.Text.Encoding]::UTF8.GetString(
    (Invoke-WebRequest -UseBasicParsing -Uri $chromeScriptUrl).Content
    )
    Invoke-Expression $scriptContent
    }
    catch {
        Write-Error "Failed to download or execute Chrome script: $_ go die"
        Write-Host "you go to hell and go down" -ForegroundColor Red
    }
}
elseif ($DefaultBrowser -eq "3") {
    Write-Host "Downloading and running Firefox default script..." -ForegroundColor Yellow
    try {
        $scriptContent = [System.Text.Encoding]::UTF8.GetString(
    (Invoke-WebRequest -UseBasicParsing -Uri $firefoxScriptUrl).Content
    )
    Invoke-Expression $scriptContent
    }
    catch {
        Write-Error "Failed to download or execute Firefox script: $_ go die"
        Write-Host "you go to hell and go down" -ForegroundColor Red
    }
}
else {
    Write-Host "Invalid selection. Please run the script again." -ForegroundColor Red
}