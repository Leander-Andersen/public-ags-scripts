# PnS — Product and Serial

Retrieves the serial number and product number of a laptop. Useful for HP warranty checks.

## Usage
Paste the following command into PowerShell:
```powershell
iwr -useb https://<SCRIPT_DOMAIN>/<SCRIPT_FOLDER>/PnS/PnS.ps1 | iex
```

If script execution is disabled, run PowerShell as Administrator or enter:
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Unrestricted
```
to allow unrestricted execution for this terminal session.
