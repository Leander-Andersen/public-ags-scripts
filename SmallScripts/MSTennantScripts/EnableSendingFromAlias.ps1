#This script enables sending emails from an alias in Outlook tennant wide
$ErrorActionPreference = 'Stop'

param(
    [Parameter(Mandatory = $false)]
    [string]$AdminUpn
)

Write-Host "Note: You need to be GA or Exchange Online admin to do this" -ForegroundColor Cyan
# Prompt for the UPN.  Read-Host keeps it as a simple string, not a secret.
$AdminUpn = Read-Host 'Enter the Global Admin UPN (e.g. admin@tenant.onmicrosoft.com)'



if (-not $AdminUpn -or $AdminUpn -eq "") {
    $AdminUpn = Read-Host "Enter the Global Admin UPN" }
    

try {
    # Ensure module is available
    if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
        Write-Host 'Installing ExchangeOnlineManagement module...'
        Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force
    }

    Import-Module ExchangeOnlineManagement -ErrorAction Stop

    # 1️⃣  Sign in with modern auth / MFA
    Connect-ExchangeOnline -UserPrincipalName $AdminUpn -ShowBanner:$false

    # 2️⃣  Check current org setting
    $isEnabled = (Get-OrganizationConfig).SendFromAliasEnabled

    if ($isEnabled) {
        Write-Host "✅  'Send from alias' is already enabled for $AdminUpn’s tenant." -ForegroundColor Green
    }
    else {
        Write-Host "⚙️  Enabling 'Send from alias'..."
        Set-OrganizationConfig -SendFromAliasEnabled $true
        $verify = (Get-OrganizationConfig).SendFromAliasEnabled
        if ($verify) {
            Write-Host "✅  Successfully enabled for $AdminUpn’s tenant." -ForegroundColor Green
        } else {
            throw "Failed to enable the feature." 
        }
    }
}
catch {
    Write-Host "❌  Error: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    # 3️⃣  Disconnect and scrub variables
    try { Disconnect-ExchangeOnline -Confirm:$false } catch {}
    Remove-Variable AdminUpn, isEnabled, verify -ErrorAction SilentlyContinue
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()
}
# Script by Leander Andersen