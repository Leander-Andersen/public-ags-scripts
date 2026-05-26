# Delete Printix

Silently uninstalls the Printix print client from a Windows machine. Checks all known install locations, stops the Printix services before removal, runs the built-in uninstaller, and writes a timestamped log to `C:\Windows\Temp\`.

Suitable for running manually, via Intune remediation, or as an RMM script.

## Usage

Run in PowerShell **as Administrator**:

```powershell
.\deletePrintix.ps1
```

No parameters required. The script is fully silent — all output goes to the console and the log file.

## What it does

| Step | Detail |
|---|---|
| Logging | Starts a transcript at `C:\Windows\Temp\scriptlog-<timestamp>.txt` |
| Path check | Looks for the Printix client in all known install locations (Program Files, Program Files (x86)) |
| Stop services | Stops `PrintixClient` and `PrintixUpdater` services if they are running |
| Uninstall | Runs `unins000.exe /SILENT` from the Printix install directory |
| Not found | If Printix is not installed the script exits cleanly with a message |
| Log saved | Transcript is closed and the log path is printed |

## Log location

```
C:\Windows\Temp\scriptlog-<yyyyMMdd-HHmmss>.txt
```

The log captures all console output and can be retrieved after the script runs for audit or troubleshooting purposes.
