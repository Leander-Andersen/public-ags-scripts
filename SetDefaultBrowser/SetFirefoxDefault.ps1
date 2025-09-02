<#
Single-file installer + maintainer (no scheduled task):
- Run once elevated (-Mode Install). It will copy itself to C:\SetdefaultBrowser\SetFirefoxDefault.ps1,
  download SetUserFTA.exe, apply defaults now, and create a Startup shortcut that re-runs
  this script in non-elevated mode (-Mode Enforce) at each user logon.
- At logon, it re-applies Firefox associations without elevation (Entra ID-friendly).
- Absolute path to STARTUP FOLDER: C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup
#>

[CmdletBinding()]
param(
    [ValidateSet('Install', 'Enforce')]
    [string]$Mode = 'Install',
    [switch]$NoElevate
)

# -------------------- Paths and constants --------------------
$installDir = "C:\SetdefaultBrowser"
$installedScript = Join-Path $installDir "SetFirefoxDefault.ps1"

$setUserFTAUrl = "https://<Domain>/<scriptFolder>/SetDefaultBrowser/SetUserFTA.exe"
$downloadFolderMachine = Join-Path $installDir "SetUserFTA"
$setUserFTAPathMachine = Join-Path $downloadFolderMachine "SetUserFTA.exe"

$userBaseDir = Join-Path $env:LOCALAPPDATA "SetdefaultBrowser"
$downloadFolderUser = Join-Path $userBaseDir "SetUserFTA"
$setUserFTAPathUser = Join-Path $downloadFolderUser "SetUserFTA.exe"

$logDirInstall = Join-Path $installDir "logs"
$logDirUser = Join-Path $userBaseDir "logs"

$pwshExe = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
$shortcutName = "EnsureFirefoxDefault.lnk"

# -------------------- Helper: Admin check and elevation (Install mode only) --------------------
function Test-IsAdmin {
    try {
        $wi = [Security.Principal.WindowsIdentity]::GetCurrent()
        $wp = New-Object Security.Principal.WindowsPrincipal($wi)
        return $wp.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { return $false }
}

$IsAdmin = Test-IsAdmin
if ($Mode -eq 'Install' -and -not $NoElevate -and -not $IsAdmin) {
    Write-Warning "This script must be run as Administrator for installation. Re-launching elevated..."
    $src = if ($PSCommandPath) { $PSCommandPath } elseif ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } else { $null }
    if ($null -eq $src) {
        Write-Error "Unable to determine script file path to re-launch elevated."
        exit 1
    }
    # Re-launch elevated in Install mode; pass -NoElevate to avoid re-prompt loops
    Start-Process -FilePath $pwshExe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$src`" -Mode Install -NoElevate"
    exit
}

# -------------------- Utility: Logging --------------------
function New-Log {
    param([ValidateSet('Install', 'Enforce')] [string]$Scope)
    $dir = if ($Scope -eq 'Install') { $logDirInstall } else { $logDirUser }
    New-Item -Path $dir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    return (Join-Path $dir ("Run-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date)))
}

# -------------------- Download/resolve SetUserFTA --------------------
function Get-SetUserFTA {
    param(
        [bool]$AllowMachineFolder = $false
    )

    # Prefer existing machine copy
    if (Test-Path $setUserFTAPathMachine) { return $setUserFTAPathMachine }
    # Or existing user copy
    if (Test-Path $setUserFTAPathUser) { return $setUserFTAPathUser }

    # Try to download where allowed
    if ($AllowMachineFolder) {
        try {
            New-Item -Path $downloadFolderMachine -ItemType Directory -Force | Out-Null
            Write-Host "Downloading SetUserFTA.exe to $setUserFTAPathMachine..."
            Invoke-WebRequest -Uri $setUserFTAUrl -OutFile $setUserFTAPathMachine -UseBasicParsing -TimeoutSec 60
            if (Test-Path $setUserFTAPathMachine) { return $setUserFTAPathMachine }
        }
        catch {
            Write-Warning "Failed to download to machine folder: $_"
        }
    }

    # Fallback to user-local copy
    try {
        New-Item -Path $downloadFolderUser -ItemType Directory -Force | Out-Null
        Write-Host "Downloading SetUserFTA.exe to $setUserFTAPathUser..."
        Invoke-WebRequest -Uri $setUserFTAUrl -OutFile $setUserFTAPathUser -UseBasicParsing -TimeoutSec 60
        if (Test-Path $setUserFTAPathUser) { return $setUserFTAPathUser }
    }
    catch {
        Write-Warning "Failed to download SetUserFTA.exe to user folder: $_"
    }

    return $null
}

# -------------------- Resolve Firefox Install ID --------------------
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
    # Fallback default
    return "308046B0AF4A39CB"
}

# -------------------- Apply associations --------------------
function Set-Firefox-Associations {
    param([string]$exePath)

    if (-not (Test-Path $exePath)) {
        Write-Warning "SetUserFTA not found at $exePath. Aborting association changes."
        return
    }

    $id = Get-FirefoxInstallId
    Write-Host "Firefox InstallID: $id"

    $ffURL = "FirefoxURL-$id"
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
        }
        else {
            Write-Host "  OK"
        }
    }
}

# -------------------- Install: copy self --------------------
function Install-Self {
    New-Item -Path $installDir -ItemType Directory -Force | Out-Null
    $src = if ($PSCommandPath) { $PSCommandPath } elseif ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } else { $null }
    if ($src -and (Test-Path $src)) {
        Copy-Item -Path $src -Destination $installedScript -Force
        Write-Host "Installed script to $installedScript"
    }
    else {
        Write-Warning "Unable to determine script file path; not copied."
    }
}

# -------------------- Startup shortcut management --------------------
function Get-CommonStartupPath {
    try {
        return [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonStartup)
    }
    catch {
        # Fallback via WScript.Shell
        $sh = New-Object -ComObject WScript.Shell
        return $sh.SpecialFolders.Item("AllUsersStartup")
    }
}

function Get-UserStartupPath {
    return [Environment]::GetFolderPath([Environment+SpecialFolder]::Startup)
}

function New-StartupShortcut {
    param(
        [string]$scriptToRun,
        [switch]$CommonScope
    )

    $startupDir = if ($CommonScope) { Get-CommonStartupPath } else { Get-UserStartupPath }
    if (-not $startupDir) {
        Write-Warning "Could not resolve Startup folder path."
        return $null
    }

    $lnkPath = Join-Path $startupDir $shortcutName
    $shell = New-Object -ComObject WScript.Shell
    $sc = $shell.CreateShortcut($lnkPath)
    $sc.TargetPath = $pwshExe
    $sc.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptToRun`" -Mode Enforce -NoElevate"
    $sc.WorkingDirectory = Split-Path $scriptToRun
    $sc.Description = "Keep Firefox as default browser at each logon"
    $sc.IconLocation = $pwshExe
    $sc.Save()

    if (Test-Path $lnkPath) {
        Write-Host "Startup shortcut created: $lnkPath"
        return $lnkPath
    }
    else {
        Write-Warning "Failed to create Startup shortcut at $lnkPath"
        return $null
    }
}

function Remove-StartupShortcut {
    $commonLnk = Join-Path (Get-CommonStartupPath) $shortcutName
    $userLnk = Join-Path (Get-UserStartupPath)   $shortcutName
    foreach ($p in @($commonLnk, $userLnk)) {
        if ($p -and (Test-Path $p)) {
            Remove-Item -Path $p -Force -ErrorAction SilentlyContinue
            Write-Host "Removed startup shortcut: $p"
        }
    }
}

# -------------------- Main flow --------------------
if ($Mode -eq 'Install') {
    # Create machine directories and install self
    New-Item -Path $logDirInstall -ItemType Directory -Force | Out-Null
    New-Item -Path $downloadFolderMachine -ItemType Directory -Force | Out-Null
    Install-Self

    $logFile = New-Log -Scope Install
    Start-Transcript -Path $logFile -Force
    try {
        # Download SetUserFTA to machine (with user fallback if needed)
        $toolPath = Get-SetUserFTA -AllowMachineFolder:$true
        if ($toolPath) {
            Set-Firefox-Associations -exePath $toolPath
        }
        else {
            Write-Warning "Could not obtain SetUserFTA; associations not changed."
        }

        # Create a Common Startup shortcut so all users re-apply at logon (non-elevated)
        $shortcut = New-StartupShortcut -scriptToRun $installedScript -CommonScope
        if (-not $shortcut) {
            # Fallback: create per-user shortcut
            Write-Warning "Falling back to per-user Startup shortcut."
            New-StartupShortcut -scriptToRun $installedScript
        }

        Write-Host "Done (Install)."
        Write-Host "Logs: $logDirInstall"
        Write-Host "To stop automatic enforcement later, remove the shortcut:"
        $commonHint = Join-Path (Get-CommonStartupPath) $shortcutName
        $userHint = Join-Path (Get-UserStartupPath)   $shortcutName
        Write-Host "  Common: $commonHint"
        Write-Host "  or User: $userHint"
    }
    catch {
        Write-Error "Error during install: $_"
    }
    finally {
        Stop-Transcript | Out-Null
    }
}
elseif ($Mode -eq 'Enforce') {
    # Per-user run at logon: no elevation, user-writable logs
    New-Item -Path $logDirUser -ItemType Directory -Force | Out-Null
    New-Item -Path $downloadFolderUser -ItemType Directory -Force | Out-Null

    $logFile = New-Log -Scope Enforce
    Start-Transcript -Path $logFile -Force
    try {
        $toolPath = Get-SetUserFTA -AllowMachineFolder:$false
        if ($toolPath) {
            Set-Firefox-Associations -exePath $toolPath
        }
        else {
            Write-Warning "Could not obtain SetUserFTA; associations not changed."
        }
        Write-Host "Done (Enforce). Logs: $logDirUser"
    }
    catch {
        Write-Error "Error during enforce: $_"
    }
    finally {
        Stop-Transcript | Out-Null
    }
}
else {
    Write-Error "Unknown Mode: $Mode. Use -Mode Install or -Mode Enforce."
}