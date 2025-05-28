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
$baseUrl = "http://script.isame12.xyz/public-ags-scripts"
$braveScriptUrl = "$baseUrl/SetBraveDefault.ps1"
$chromeScriptUrl = "$baseUrl/SetChromeDefault.ps1" 
$firefoxScriptUrl = "$baseUrl/SetFirefoxDefault.ps1"

# Run the appropriate script based on user selection
if ($DefaultBrowser -eq "1") {
    Write-Host "Downloading and running Brave default script..." -ForegroundColor Yellow
    try {
        $braveScript = Invoke-WebRequest -Uri $braveScriptUrl -UseBasicParsing
        if ($braveScript.StatusCode -eq 200) {
            Write-Host "Successfully downloaded Brave script. Executing..." -ForegroundColor Green
            Invoke-Expression $braveScript.Content
        } else {
            Write-Error "Failed to download Brave script. HTTP Status: $($braveScript.StatusCode)"
        }
    }
    catch {
        Write-Error "Failed to download or execute Brave script: $_"
        Write-Host "Please check your internet connection and that the script URL is accessible." -ForegroundColor Red
    }
}
elseif ($DefaultBrowser -eq "2") {
    Write-Host "Downloading and running Chrome default script..." -ForegroundColor Yellow
    try {
        $chromeScript = Invoke-WebRequest -Uri $chromeScriptUrl -UseBasicParsing
        if ($chromeScript.StatusCode -eq 200) {
            Write-Host "Successfully downloaded Chrome script. Executing..." -ForegroundColor Green
            Invoke-Expression $chromeScript.Content
        } else {
            Write-Error "Failed to download Chrome script. HTTP Status: $($chromeScript.StatusCode)"
        }
    }
    catch {
        Write-Error "Failed to download or execute Chrome script: $_"
        Write-Host "Please check your internet connection and that the script URL is accessible." -ForegroundColor Red
    }
}
elseif ($DefaultBrowser -eq "3") {
    Write-Host "Downloading and running Firefox default script..." -ForegroundColor Yellow
    try {
        $firefoxScript = Invoke-WebRequest -Uri $firefoxScriptUrl -UseBasicParsing
        if ($firefoxScript.StatusCode -eq 200) {
            Write-Host "Successfully downloaded Firefox script. Executing..." -ForegroundColor Green
            Invoke-Expression $firefoxScript.Content
        } else {
            Write-Error "Failed to download Firefox script. HTTP Status: $($firefoxScript.StatusCode)"
        }
    }
    catch {
        Write-Error "Failed to download or execute Firefox script: $_"
        Write-Host "Please check your internet connection and that the script URL is accessible." -ForegroundColor Red
    }
}
else {
    Write-Host "Invalid selection. Please choose 1, 2, or 3." -ForegroundColor Red
    exit
}

Write-Host "Script execution completed!" -ForegroundColor Green
Write-Host "Press any key to continue..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")