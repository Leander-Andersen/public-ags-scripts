# Hextract — Hardware Hash Generator

Generates a hardware hash for Windows Autopilot enrollment from the command line.

## Usage
Paste the following command into PowerShell:
```powershell
iwr -useb https://<SCRIPT_DOMAIN>/<SCRIPT_FOLDER>/Hextract/Hextract.ps1 | iex
```

If script execution is disabled, run PowerShell as Administrator or enter:
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Unrestricted
```
to allow unrestricted execution for this terminal session.

Output will be saved to: `C:\HWID\`
