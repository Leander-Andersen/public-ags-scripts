[CmdletBinding()]
param(
[ValidateSet('Brave', 'Chrome', 'Firefox', 'Remove')]
[string]$Browser
)

#URLs (use HTTPS)
$urls = @{
Brave   = 'https://script.isame12.xyz/public-ags-scripts/SetDefaultBrowser/SetBraveDefault.ps1'
Chrome  = 'https://script.isame12.xyz/public-ags-scripts/SetDefaultBrowser/SetChromeDefault.ps1'
Firefox = 'https://script.isame12.xyz/public-ags-scripts/SetDefaultBrowser/SetFirefoxDefault.ps1'
}

#Ensure TLS 1.2 is enabled for older PowerShell/WinHTTP stacks
try {
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {
Write-Host "Failed to set TLS 1.2"
}

function Invoke-RemoteScriptElevated {
param(
[Parameter(Mandatory)]
[ValidateSet('Brave', 'Chrome', 'Firefox', 'Remove')]
[string]$Browser
)
if ($Browser -eq 'Remove') {
    # Ensure we are elevated (relaunch self if needed)
    $selfPath = if ($PSCommandPath) { $PSCommandPath } elseif ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } else { $null }
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        if ($selfPath) {
            $pwsh = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
            $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$selfPath`" -Browser Remove"
            try {
                Start-Process -FilePath $pwsh -Verb RunAs -ArgumentList $arguments | Out-Null
            } catch {
                Write-Error "Elevation failed: $($_.Exception.Message)"
            }
        } else {
            Write-Warning "Cannot self-relaunch with elevation because the script path is unknown. Please re-run as Administrator with -Browser Remove."
        }
        return
    }

    Write-Host "Removing default browser configuration..." -ForegroundColor Yellow

    # Remove machine-wide Startup link
    $commonStartup = [Environment]::GetFolderPath('CommonStartup')
    $startupLink = Join-Path $commonStartup 'EnsureFirefoxDefault.lnk'
    if (Test-Path $startupLink) {
        try {
            Remove-Item $startupLink -Force -ErrorAction Stop
            Write-Host "Removed Startup link: $startupLink" -ForegroundColor Green
        } catch {
            Write-Warning "Failed to remove Startup link: $($_.Exception.Message)"
        }
    } else {
        Write-Host "No Startup link found at: $startupLink" -ForegroundColor Yellow
    }

    
    # Remove scheduled tasks matching Ensure(Brave|Chrome|Firefox)Default
    try {
        $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
            $_.TaskName -match '^Ensure(Brave|Chrome|Firefox)Default$'
        }
        if ($tasks) {
            foreach ($t in $tasks) {
                try {
                    Unregister-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -Confirm:$false
                    Write-Host "Removed scheduled task: $($t.TaskPath)$($t.TaskName)" -ForegroundColor Green
                } catch {
                    Write-Warning "Failed to remove scheduled task $($t.TaskName): $($_.Exception.Message)"
                }
            }
        } else {
            Write-Host "No matching scheduled tasks found." -ForegroundColor Yellow
        }
    } catch {
        Write-Warning "Enumerating scheduled tasks failed: $($_.Exception.Message)"
    }

    Write-Host "Default browser configuration removed." -ForegroundColor Green
    return
}

# ----- Install / Set default flow -----
$url = $urls[$Browser]
if (-not $url) { throw "No URL mapped for $Browser" }

# Download to a temp file so the script can resolve its own path ($PSCommandPath)
$tmpDir = Join-Path $env:TEMP 'DefaultBrowserBootstrap'
try { New-Item -Path $tmpDir -ItemType Directory -Force | Out-Null } catch {}

$fileName = [IO.Path]::GetFileName($url)
if (-not $fileName -or -not $fileName.ToLower().EndsWith('.ps1')) { $fileName = "$Browser.ps1" }
$dest = Join-Path $tmpDir $fileName

Write-Host "Downloading $Browser script..." -ForegroundColor Yellow
try {
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $dest -TimeoutSec 60 -ErrorAction Stop
} catch {
    throw "Download failed from ${url}: $($_.Exception.Message)"
}

if (-not (Test-Path $dest)) { throw "Download failed: ${url}" }

# Run elevated so it can install files and create the Startup link for all users
$pwsh = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
$arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$dest`""

Write-Host "Launching $Browser installer elevated..." -ForegroundColor Cyan
try {
    $p = Start-Process -FilePath $pwsh -Verb RunAs -ArgumentList $arguments -Wait -PassThru
} catch {
    throw "Failed to launch elevated process: $($_.Exception.Message)"
}

if ($p -and $p.ExitCode -ne 0) {
    Write-Warning "$Browser script exited with code $($p.ExitCode)"
} else {
    Write-Host "$Browser default configuration completed." -ForegroundColor Green
}
}
#Interactive prompt if -Browser not supplied
if (-not $PSBoundParameters.ContainsKey('Browser')) {
Write-Host "What browser do you want as default?" -ForegroundColor Cyan
Write-Host "(1) Brave"
Write-Host "(2) Chrome"
Write-Host "(3) Firefox"
Write-Host "(4) Remove"
$choice = Read-Host "Enter your choice"
switch ($choice) {
    '1' { $Browser = 'Brave' }
    '2' { $Browser = 'Chrome' }
    '3' { $Browser = 'Firefox' }
    '4' { $Browser = 'Remove' }
    default {
        Write-Host "Invalid selection. Status: FYN" -ForegroundColor Red
        exit 1
    }
}
}

Invoke-RemoteScriptElevated -Browser $Browser