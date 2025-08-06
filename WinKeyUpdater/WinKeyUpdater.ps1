#Lets start by identefying current os

$osVersion = Invoke-Expression '(Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").EditionID'

#Lets see if you can upgrade this version

if ($osVersion -eq "Home") {
    
}
else {
    Write-Warning "Wah, You are already running a bussiness version of windows. Are you sure you want to continue?"
    $continue = Read-Host "y/n" 

    if ($continue -eq "n") {
        exit
    }
}

function ckOsVersion {
    # Check edition again
    $newEdition = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").EditionID
    if ($newEdition -eq "Professional" -or $newEdition -eq "Enterprice") {
        Write-Output "succeeded: Edition is now Professional and should be activated."
        Invoke-Expression "slmgr /dlv"
        exit
    }
    else {
        throw "Edition not changed."
    }
    
}

#Get current key and back it up to a text file unde current user profile
$regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
$currentKey = (Get-ItemProperty -Path $regPath).DigitalProductId
$currentKey | Out-File -FilePath "$env:USERPROFILE\Desktop\CurrentKeyBackup.txt"

#write this to the console
Write-Output "Current Windows key: $currentKey"
Write-Output "Current Windows key has been backed up to $env:USERPROFILE\Desktop\CurrentKeyBackup.txt"


#Get the new key from the user
$newKey = Read-Host "Please enter your new Windows key"

#Define ways of applying the new key
function method1 {
    param (
        [string]$newKey
    )

    #Set key to generic pro key
    Invoke-Expression 'slmgr /ipk VK7JG-NPHTM-C97JM-9MPGT-3V66T'
    

    # Now apply real upgrade key
    Invoke-Expression "slmgr /ipk $newKey"
    Start-Sleep -Seconds 3
    Invoke-Expression "slmgr /ato"
    Start-Sleep -Seconds 5

    # Check if edition changed
    ckOsVersion
    
}






function method2 {
    param (
        [string]$newKey
    )

    try {
        # Set generic key via slmgr (CLI fallback still helpful here)
        Invoke-Expression "slmgr /ipk VK7JG-NPHTM-C97JM-9MPGT-3V66T"
        Start-Sleep -Seconds 2

        # Now launch GUI-based edition switch
        Start-Process -FilePath "changepk.exe" -ArgumentList "/productkey VK7JG-NPHTM-C97JM-9MPGT-3V66T" -Wait
        Write-Output "Edition change process initiated. A reboot will likely be required."

        $doReboot = Read-Host "Reboot now to continue upgrade? (y/n)"
        if ($doReboot -eq "y") {
            Restart-Computer -Force
        }
        else {
            Write-Output "Please reboot manually. After reboot, re-run this script to complete activation."
        }
    }
    catch {
        Write-Error "Method 2 failed. Manual intervention may be required."
    }
    # Check if edition changed
    ckOsVersion
}



method1($newKey)
method2($newKey)