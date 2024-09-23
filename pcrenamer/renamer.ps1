Write-Host """
Pc-Renamer
"""

#forsikrer at scriptet køres som administrator, om ikke, så avsluttes scriptet
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Please run this script as an Administrator."
    exit
}

$newPcName = Read-Host "Enter the new PC name: "

Rename-Computer -NewName $newPcName
#ask user if he wants to restart when script is done and store it in $restartNow
$restartNow = Read-Host "Do you want to restart now? (y/n)"

if ($restartNow -eq "y") {
    Restart-Computer
}