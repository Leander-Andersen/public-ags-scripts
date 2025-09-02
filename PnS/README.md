# PnS   | Product and Serial
## A small script to retrieve both the serial number and product number of laptops (sometimes required to do a warranty check on HP computers)

To use, paste the following command into PowerShell:
```powershell
iwr -useb https://<Domain>/<scriptFolder>/PnS/PnS.ps1 | iex
```
If script execution is disabled, run PowerShell as Administrator or enter: 
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Unrestricted
```
to allow unrestricted execution for this terminal session.