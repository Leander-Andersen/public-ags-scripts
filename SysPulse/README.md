# SysPulse — Windows System Diagnostic & Analysis Tool

Collects, analyses, and reports on hardware, firmware, drivers, power, security, and event-log data on any Windows machine regardless of manufacturer. All output is written to a timestamped folder on the desktop so results can be attached to a support ticket or reviewed offline.

Requires Windows 10/11, PowerShell 5.1+, and must be run as Administrator for full data collection.

## Usage
Paste the following command into PowerShell **as Administrator**:
```powershell
iwr -useb https://<SCRIPT_DOMAIN>/<SCRIPT_FOLDER>/SysPulse/SysPulse.ps1 | iex
```

If script execution is disabled, run PowerShell as Administrator or enter:
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Unrestricted
```
to allow unrestricted execution for this terminal session.

## What it collects

| Category | Details |
|---|---|
| System & BIOS | Processor detection, BIOS/firmware info, EC and touchpad firmware versions |
| Power & Battery | Power button/lid/critical battery actions, power slider, charge percentage, temperature |
| Hardware | Bluetooth info, Device Manager status, memory details, display scale, DSC status |
| Applications | Teams, Office, Zoom versions; arbitrary program install check |
| Events & History | Reboot history, unexpected shutdown count, Windows Error Reporting events |
| System Health | Known issues scan, missing Windows Updates |
| Crash Dumps | Kernel dumps, minidumps |
| Analysis | Idle analysis, HTML report generation |

## Output

Results are saved to a timestamped folder on the desktop:
```
C:\Users\<username>\Desktop\SysPulse_<serial>_<timestamp>\
```
