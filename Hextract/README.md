# HExtract — Autopilot Hardware Hash Generator

Generates a Windows Autopilot hardware hash CSV and optionally emails it directly to a recipient. Credentials can be pre-packaged with AES-256 encryption so the script can be distributed to technicians without them ever seeing or entering SMTP details.

Requires Windows 10/11, PowerShell 5.1+, and must be run as Administrator.

## Usage
Paste the following command into PowerShell **as Administrator**:
```powershell
iwr -useb https://<SCRIPT_DOMAIN>/<SCRIPT_FOLDER>/Hextract/Hextract.ps1 | iex
```

If script execution is disabled, run PowerShell as Administrator or enter:
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Unrestricted
```
to allow unrestricted execution for this terminal session.

## What it does

| Step | Details |
|---|---|
| Hash generation | Collects the device hardware hash, serial number, and Windows Product ID via WMI/CIM |
| Output | Saves a CSV named after the computer to `C:\HWID\` |
| Email delivery | Attaches the CSV and sends it over SMTP — either automatically or on technician request |
| Self-delete | The packaged script removes itself after a successful send so credentials do not linger |

## SMTP packaging (for IT deployment)

Run the script once on your own machine and choose **[P]** to embed SMTP credentials. This produces a `Hextract_pkg.ps1` with an AES-256 encrypted password baked in. Distribute that file to technicians — they never see or enter any credentials.

| Packaged with a fixed recipient | Packaged without a recipient | Not packaged |
|---|---|---|
| Generates hash → sends automatically → self-deletes | Generates hash → technician enters their own address → sends → self-deletes | Generates hash → interactive menu with email and packaging options |

## Output

Hash CSV is saved to:
```
C:\HWID\<COMPUTERNAME>.csv
```
