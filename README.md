# Script Library

A collection of PowerShell and web scripts to make IT work easier.

## Branch structure
- `main` — finished, stable features
- `Experimental` — new features that *should* work
- Feature branches — work in progress

## Deploying to a web server

Run this one-liner on your server (requires git, curl, sudo):

```bash
curl -s https://raw.githubusercontent.com/Leander-Andersen/public-ags-scripts/main/install.sh | bash -s -- --webroot /var/www/html --scripts-folder <SCRIPT_FOLDER>
```

Then open `https://<SCRIPT_DOMAIN>/<SCRIPT_FOLDER>/setup.php` in a browser, enter your domain and folder name, and the setup script will rewrite all URLs automatically.

## Script URLs after setup

```
https://<SCRIPT_DOMAIN>/<SCRIPT_FOLDER>/SetDefaultBrowser/SetDefaultBrowser.ps1
https://<SCRIPT_DOMAIN>/<SCRIPT_FOLDER>/Hextract/Hextract.ps1
https://<SCRIPT_DOMAIN>/<SCRIPT_FOLDER>/PnS/PnS.ps1
```
