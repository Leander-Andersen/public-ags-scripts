# This script generates a hardware hash from the command line.
## Usage
To run, paste the following command into PowerShell:
```powershell
iwr -useb http://script.isame12.no/public-ags-scripts/Hextract/Hextract.ps1 | iex
 ```
If script execution is disabled, run PowerShell as Administrator or enter:
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Unrestricted
 ```
to allow unrestricted execution for this terminal session.

Output will be saved to: C:\HWID\