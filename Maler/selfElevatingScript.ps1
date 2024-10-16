
#forsikrer at scriptet køres som administrator, om ikke, så opnes ett nytt vindu som kjører scriptet som administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Please run this script as an Administrator."
    $runAsAdmin = Read-Host "Do you want to run this script as an Administrator? (Y/N)"
    
    if ($runAsAdmin -eq "Y" -or $runAsAdmin -eq "y" -or $runAsAdmin -eq "Yes" -or $runAsAdmin -eq "yes") {
        #starten en ny prosess som kjører scriptet som administrator
        Start-Process powershell -Verb RunAs -ArgumentList ('-noprofile -noexit -file "{0}"' -f ($MyInvocation.MyCommand.Definition))    
    }
    else {
        exit
    }
    

}
else {
    Write-Warning "Running as Administrator"
}

