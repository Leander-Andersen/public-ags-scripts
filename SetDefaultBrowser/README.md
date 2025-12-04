# SetDefaultBrowser – Zero‑download usage

Run straight from the web. No local bootstrap needed.

## Quick start (interactive menu)
Windows PowerShell 5.1:
```powershell
iwr -useb https://script.isame12.no/public-ags-scripts/SetDefaultBrowser/SetDefaultBrowser.ps1 | iex
```

PowerShell 7+:
```powershell
iwr https://script.isame12.no/public-ags-scripts/SetDefaultBrowser/SetDefaultBrowser.ps1 | iex
```

You’ll get a menu:
- (1) Brave
- (2) Chrome
- (3) Firefox
- (4) Remove
- (Q) Quit

## Unattended usage (pass parameters)
Use this form to pass -Browser without downloading the file.

Windows PowerShell 5.1:
```powershell
iex "& { $(iwr -useb https://script.isame12.no/public-ags-scripts/SetDefaultBrowser/SetDefaultBrowser.ps1) } -Browser Chrome"
```

PowerShell 7+:
```powershell
iex "& { $(iwr https://script.isame12.no/public-ags-scripts/SetDefaultBrowser/SetDefaultBrowser.ps1) } -Browser Chrome"
```

Accepted values:
- -Browser Brave
- -Browser Chrome
- -Browser Firefox
- -Browser Remove  (cleans scheduled tasks, Startup links, temp payloads)

Examples:
```powershell
# Set Brave
iex "& { $(iwr -useb https://script.isame12.no/public-ags-scripts/SetDefaultBrowser/SetDefaultBrowser.ps1) } -Browser Brave"
```
```powershell
# Remove enforcement artifacts
iex "& { $(iwr -useb https://script.isame12.no/public-ags-scripts/SetDefaultBrowser/SetDefaultBrowser.ps1) } -Browser Remove"
```

## Notes
- Elevation: the script will prompt for UAC when needed.
- PS versions: -UseBasicParsing (-useb) exists in Windows PowerShell 5.1 only. Drop it on PowerShell 7+.
- No cleanup needed: the one‑liner leaves no local bootstrap behind.

## Troubleshooting
- “A parameter cannot be found that matches ‘UseBasicParsing’”: you’re on PowerShell 7+. Remove -useb.
- “Running scripts is disabled”: irrelevant here; you’re executing a string via iex. If your org enforces Constrained Language Mode, run from an elevated 5.1 console or fix policy.