# Set Default Browser Script

  

This script bypasses the default browser Intune policy by using the personal version of **SetUserFTA** and creating a task at logon to set the browser to the desired type.

  

🔗 [SetUserFTA website](https://setuserfta.com/)

---

## Usage

  

Paste the following command into PowerShell:

  

```powershell

iwr -useb https://script.isame12.xyz/public-ags-scripts/SetDefaultBrowser/SetDefaultBrowser.ps1 | iex

 ```

If script execution is disabled, run PowerShell as Administrator or enter:
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Unrestricted
```