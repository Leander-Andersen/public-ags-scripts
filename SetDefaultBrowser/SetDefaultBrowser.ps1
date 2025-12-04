[CmdletBinding()]
param(
    [ValidateSet('Brave','Chrome','Firefox','Remove')]
    [string]$Browser,
    [switch]$DeleteSelf
)

# --- URLs for the remote installers (HTTPS only) ---
$urls = @{
    Brave   = 'https://script.isame12.no/public-ags-scripts/SetDefaultBrowser/SetBraveDefault.ps1'
    Chrome  = 'https://script.isame12.no/public-ags-scripts/SetDefaultBrowser/SetChromeDefault.ps1'
    Firefox = 'https://script.isame12.no/public-ags-scripts/SetDefaultBrowser/SetFirefoxDefault.ps1'
}

# --- Ensure TLS 1.2 for older stacks ---
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

function Test-IsAdmin {
    try {
        return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Start-SelfDelete {
    param([Parameter(Mandatory)][string]$Path)
    try {
        Start-Process -WindowStyle Hidden -FilePath "$env:ComSpec" -ArgumentList "/c ping 127.0.0.1 -n 3 > nul & del /f /q ""$Path""" | Out-Null
    } catch {}
}

function Remove-DefaultBrowserAssets {
    # Must be elevated; relaunch self if not
    if (-not (Test-IsAdmin)) {
        $self = if ($PSCommandPath) { $PSCommandPath } elseif ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } else { $null }
        if ($self) {
            $pwsh = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
            $args = "-NoProfile -ExecutionPolicy Bypass -File `"$self`" -Browser Remove" + ($(if ($DeleteSelf) { ' -DeleteSelf' } else { '' }))
            try { Start-Process -FilePath $pwsh -Verb RunAs -ArgumentList $args | Out-Null } catch { Write-Error "Elevation failed: $($_.Exception.Message)" }
        } else {
            Write-Warning "Unknown script path; re-run as Administrator: -Browser Remove"
        }
        return
    }

    Write-Host "Removing default-browser enforcement artifacts..." -ForegroundColor Yellow

    # Remove Startup links for all supported browsers
    $commonStartup = [Environment]::GetFolderPath('CommonStartup')
    @('Brave','Chrome','Firefox').ForEach({
        $lnk = Join-Path $commonStartup ("Ensure{0}Default.lnk" -f $_)
        if (Test-Path $lnk) {
            try { Remove-Item -LiteralPath $lnk -Force -ErrorAction Stop; Write-Host "Removed Startup link: $lnk" -ForegroundColor Green }
            catch { Write-Warning "Failed to remove $($lnk): $($.Exception.Message)" }
        }
    })

    # Remove scheduled tasks Ensure(Brave|Chrome|Firefox)Default anywhere
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

    # Remove temp payload folder
    $tmpDir = Join-Path $env:TEMP 'DefaultBrowserBootstrap'
    if (Test-Path $tmpDir) {
        try { Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction Stop; Write-Host "Cleaned: $tmpDir" -ForegroundColor Green }
        catch { Write-Warning "Failed to clean temp: $($_.Exception.Message)" }
    }

    Write-Host "Default-browser enforcement removed." -ForegroundColor Green

    if ($DeleteSelf) {
        $self = if ($PSCommandPath) { $PSCommandPath } elseif ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } else { $null }
        if ($self -and (Test-Path $self)) {
            Write-Host "Scheduling self-delete..." -ForegroundColor Yellow
            Start-SelfDelete -Path $self
        }
    }
}

function Invoke-RemoteScriptElevated {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Brave','Chrome','Firefox')]
        [string]$Browser
    )

    $url = $urls[$Browser]
    if (-not $url) { throw "No URL mapped for $Browser" }

    $tmpDir = Join-Path $env:TEMP 'DefaultBrowserBootstrap'
    try { New-Item -Path $tmpDir -ItemType Directory -Force | Out-Null } catch {}

    $fileName = [IO.Path]::GetFileName($url)
    if (-not $fileName -or -not $fileName.ToLower().EndsWith('.ps1')) { $fileName = "$Browser.ps1" }
    $dest = Join-Path $tmpDir $fileName

    Write-Host "Downloading $Browser script..." -ForegroundColor Yellow
    try {
        Invoke-WebRequest -Uri $url -OutFile $dest -TimeoutSec 60 -ErrorAction Stop
    } catch {
        throw "Download failed from ${url}: $($_.Exception.Message)"
    }

    if (-not (Test-Path $dest)) { throw "Download failed: ${url}" }

    $pwsh = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
    $args = "-NoProfile -ExecutionPolicy Bypass -File `"$dest`""

    Write-Host "Launching $Browser installer elevated..." -ForegroundColor Cyan
    try {
        $p = Start-Process -FilePath $pwsh -Verb RunAs -ArgumentList $args -Wait -PassThru
    } catch {
        throw "Failed to launch elevated process: $($_.Exception.Message)"
    }

    if ($p -and $p.ExitCode -ne 0) {
        Write-Warning "$Browser script exited with code $($p.ExitCode)"
    } else {
        Write-Host "$Browser default configuration completed." -ForegroundColor Green
    }
}

function Read-MenuChoice {
    while ($true) {
        Write-Host "What browser do you want as default?" -ForegroundColor Cyan
        Write-Host "(1) Brave"
        Write-Host "(2) Chrome"
        Write-Host "(3) Firefox"
        Write-Host "(4) Remove"
        Write-Host "(Q) Quit"
        $choice = Read-Host "Enter your choice"
        switch ($choice.Trim()) {
            '1' { return 'Brave' }
            '2' { return 'Chrome' }
            '3' { return 'Firefox' }
            '4' { return 'Remove' }
            { $_ -match '^(q|quit)$' } { return $null }
            default { Write-Host "Invalid selection." -ForegroundColor Red }
        }
    }
}

# --- Main flow: allow param-less or parameterized use ---
if (-not $PSBoundParameters.ContainsKey('Browser') -or [string]::IsNullOrWhiteSpace($Browser)) {
    $Browser = Read-MenuChoice
    if (-not $Browser) { return }
}

if ($Browser -eq 'Remove') {
    Remove-DefaultBrowserAssets
    return
}

Invoke-RemoteScriptElevated -Browser $Browser
if ($DeleteSelf) {
    $self = if ($PSCommandPath) { $PSCommandPath } elseif ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } else { $null }
    if ($self -and (Test-Path $self)) {
        Write-Host "Scheduling self-delete..." -ForegroundColor Yellow
        Start-SelfDelete -Path $self
    }
}