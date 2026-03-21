# AGS Script Library

A collection of PowerShell and web scripts to make IT work easier. Scripts are self-hosted on your own web server so you can run them on any machine with a single one-liner, no files to copy around.

---

## Requirements

- A Linux web server running **Apache** or **Nginx** with **PHP 8.0+**
- **git** installed on the server
- Root / sudo access for the initial install

---

## Quick install

SSH into your server and run:

```bash
curl -fsSL https://raw.githubusercontent.com/Leander-Andersen/public-ags-scripts/main/install.sh | sudo bash
```

This uses all defaults: web root `/var/www/html`, scripts folder `scripts`.

---

## Full install with options

If you want to customise the paths, download the script first and pass arguments:

```bash
curl -fsSL https://raw.githubusercontent.com/Leander-Andersen/public-ags-scripts/main/install.sh -o install.sh
sudo bash install.sh --webroot /var/www/html --scripts-folder scripts
```

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `--webroot` | `/var/www/html` | Absolute path to your web server's document root. |
| `--scripts-folder` | `scripts` | Name of the folder the scripts will live in under the web root. This becomes the URL path segment, e.g. `https://yourserver.com/scripts/`. Must be alphanumeric (hyphens and underscores allowed, no spaces). |
| `--user` | auto-detected | The OS user your web server runs as (`www-data`, `apache`, `nginx`). The installer tries to detect this automatically — only pass it if detection fails. |
| `--branch` | `main` | Which git branch to install from. Use `main` for stable releases. |

### What the installer does

1. **Clones the repository** into `<webroot>/<scripts-folder>/`
   If the destination already exists, it does a hard reset to the latest commit instead.
2. **Copies the file browser** (`index.php`, `viewer.php`, `globalVariables.php`) from the repo to the web root so they serve from `https://yourserver.com/`.
3. **Sets file ownership** on everything it touched to the web server user.
4. Prints the URL for the next step.

---

## After install — run setup.php

Open a browser and go to:

```
http://your-server/<scripts-folder>/setup.php
```

Enter two values:

- **Script domain** — the domain or subdomain this server is reachable at (e.g. `scripts.yourdomain.com`). No `https://`, no trailing slash.
- **Folder name** — must match the `--scripts-folder` you used during install (e.g. `scripts`).

Setup will scan every script in the library, show you a diff of every line that will change, and wait for you to confirm before writing anything. Once applied it:

- Rewrites all domain and folder placeholders across every `.ps1`, `.php`, `.sh`, and other text file in the library
- Renames the scripts folder on disk to match what you entered
- Saves your settings to `.setup-config.json` so updates can re-apply them automatically
- Creates `setup.lock` to prevent accidental re-runs

After setup your scripts are live. Example (using `scripts.yourdomain.com` and folder `scripts`):

```
https://scripts.yourdomain.com/scripts/SetDefaultBrowser/SetDefaultBrowser.ps1
https://scripts.yourdomain.com/scripts/Hextract/Hextract.ps1
https://scripts.yourdomain.com/scripts/PnS/PnS.ps1
```

---

## Updating

Once the library is set up, visit `https://your-domain/your-folder/update.php`.

The updater will:

1. Fetch the latest commits from GitHub
2. Show you a summary of what changed
3. Pull the changes with a hard reset to the selected branch
4. Automatically re-apply your saved domain and folder settings from `.setup-config.json`

You do not need to re-run setup.php or the installer after an update — your configuration is preserved.

---

## File browser

The installer places a file browser at the web root (`index.php`) so visiting `https://yourserver.com/` shows a navigable directory listing of all your scripts. Features:

- Click any folder to browse into it
- Click any `.md` file to render it as formatted markdown (via `viewer.php`)
- Click any `.ps1` or other file to download / view it directly
- Dark, light, and OverPinku theme with toggle button (preference saved per-browser)

---

## Available scripts

| Script | What it does |
|---|---|
| [SetDefaultBrowser](SetDefaultBrowser/README.md) | Sets the default browser on Windows via an interactive menu or silent parameters. Supports Chrome, Firefox, Brave, and removal. |
| [Hextract](Hextract/README.md) | Generates a hardware hash for Windows Autopilot enrollment. |
| [PnS](PnS/README.md) | Retrieves the product name and serial number from a laptop (useful for warranty lookups). |

---

## Branch structure

| Branch | Purpose |
|---|---|
| `main` | Stable releases — what the installer pulls by default |
| `experimental` | New features that work but aren't fully hardened yet |
| Feature branches | Work in progress |
