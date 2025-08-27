[CmdletBinding()]
param(
    [ValidateSet('Brave','Chrome','Firefox')]
    [string]$Browser
)

# URLs (use HTTPS)
$urls = @{
    Brave   = 'https://script.isame12.xyz/public-ags-scripts/SetDefaultBrowser/SetBraveDefault.ps1'
    Chrome  = 'https://script.isame12.xyz/public-ags-scripts/SetDefaultBrowser/SetChromeDefault.ps1'
    Firefox = 'https://script.isame12.xyz/public-ags-scripts/SetDefaultBrowser/SetFirefoxDefault.ps1'
}

# Ensure TLS 1.2 is enabled for older PowerShell/WinHTTP stacks
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {Write-Host "Failed to set TLS 1.2"}

function Invoke-RemoteScriptElevated {
    param(
        [Parameter(Mandatory)][ValidateSet('Brave','Chrome','Firefox')] [string]$Browser
    )

    $url = $urls[$Browser]
    if (-not $url) { throw "No URL mapped for $Browser" }

    # Download to a temp file so the script can resolve its own path ($PSCommandPath)
    $tmpDir = Join-Path $env:TEMP 'DefaultBrowserBootstrap'
    New-Item -Path $tmpDir -ItemType Directory -Force | Out-Null

    $fileName = [IO.Path]::GetFileName($url)
    if (-not $fileName -or -not $fileName.ToLower().EndsWith('.ps1')) { $fileName = "$Browser.ps1" }
    $dest = Join-Path $tmpDir $fileName

    Write-Host "Downloading $Browser script..." -ForegroundColor Yellow
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $dest -TimeoutSec 60

    if (-not (Test-Path $dest)) { throw "Download failed: $url" }

    # Run elevated so it can install files and create the Startup link for all users
    $pwsh = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
    $args = "-NoProfile -ExecutionPolicy Bypass -File `"$dest`""

    Write-Host "Launching $Browser installer elevated..." -ForegroundColor Cyan
    $p = Start-Process -FilePath $pwsh -Verb RunAs -ArgumentList $args -Wait -PassThru
    if ($p.ExitCode -ne 0) {
        Write-Warning "$Browser script exited with code $($p.ExitCode)"
    } else {
        Write-Host "$Browser default configuration completed." -ForegroundColor Green
    }
}

# Interactive prompt if -Browser not supplied
if (-not $PSBoundParameters.ContainsKey('Browser')) {
    Write-Host "What browser do you want as default?" -ForegroundColor Cyan
    Write-Host "(1) Brave"
    Write-Host "(2) Chrome"
    Write-Host "(3) Firefox"
    $choice = Read-Host "Enter your choice"

    switch ($choice) {
        '1' { $Browser = 'Brave' }
        '2' { $Browser = 'Chrome' }
        '3' { $Browser = 'Firefox' }
        default {
            Write-Host "Invalid selection. Status: FYN 💔🥀" -ForegroundColor Red
            exit 1
        }
    }
}

Invoke-RemoteScriptElevated -Browser $Browser