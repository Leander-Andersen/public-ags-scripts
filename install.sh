#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# AGS Script Library — one-command installer
#
# Result after install:
#   WEBROOT/index.php          ← file browser
#   WEBROOT/viewer.php         ← markdown viewer
#   WEBROOT/SCRIPTS_FOLDER/    ← all scripts (SetDefaultBrowser, etc.)
#   WEBROOT/SCRIPTS_FOLDER/setup.php
#   WEBROOT/SCRIPTS_FOLDER/update.php
#
# Usage (run as root or with sudo):
#   sudo bash install.sh
#
# Optional arguments:
#   --webroot       /var/www/html   (default: /var/www/html)
#   --scripts-folder  scripts       (default: scripts)
#   --user          www-data        (default: auto-detected)
#   --branch        main            (default: main)
# ─────────────────────────────────────────────────────────────────────────────
set -e

REPO_URL="https://github.com/Leander-Andersen/public-ags-scripts.git"
WEBROOT="/var/www/html"
SCRIPTS_FOLDER="scripts"
BRANCH="main"
WEB_USER=""

# ── Parse arguments ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --webroot)        WEBROOT="$2";        shift 2 ;;
        --scripts-folder) SCRIPTS_FOLDER="$2"; shift 2 ;;
        --user)           WEB_USER="$2";       shift 2 ;;
        --branch)         BRANCH="$2";         shift 2 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

DEST="$WEBROOT/$SCRIPTS_FOLDER"

# ── Auto-detect web server user ───────────────────────────────────────────────
if [[ -z "$WEB_USER" ]]; then
    if id "www-data" &>/dev/null; then
        WEB_USER="www-data"
    elif id "apache" &>/dev/null; then
        WEB_USER="apache"
    elif id "nginx" &>/dev/null; then
        WEB_USER="nginx"
    else
        echo "Could not auto-detect web server user. Pass --user <username>"
        exit 1
    fi
fi

# ── Must run as root ──────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo "Please run as root:  sudo bash install.sh"
    exit 1
fi

echo ""
echo "  Web root       : $WEBROOT"
echo "  Scripts folder : $SCRIPTS_FOLDER  (URL: http://your-server/$SCRIPTS_FOLDER/)"
echo "  Branch         : $BRANCH"
echo "  Web user       : $WEB_USER"
echo ""

# ── Clone or update repo ──────────────────────────────────────────────────────
if [[ -d "$DEST/.git" ]]; then
    echo "[1/4] Repo already exists — pulling latest..."
    git config --global --add safe.directory "$DEST" 2>/dev/null || true
    git -C "$DEST" fetch origin
    git -C "$DEST" reset --hard "origin/$BRANCH"
else
    echo "[1/4] Cloning repository..."
    git clone --branch "$BRANCH" "$REPO_URL" "$DEST"
fi

# ── Deploy web root files from ##Extras ───────────────────────────────────────
echo "[2/4] Copying file browser to web root..."
EXTRAS="$DEST/##Extras"
for f in index.php viewer.php globalVariables.php; do
    if [[ -f "$EXTRAS/$f" ]]; then
        cp "$EXTRAS/$f" "$WEBROOT/$f"
        echo "      → $WEBROOT/$f"
    fi
done

# ── Set ownership ─────────────────────────────────────────────────────────────
echo "[3/4] Setting ownership to $WEB_USER..."
chown -R "$WEB_USER":"$WEB_USER" "$DEST"
# Chown the web root dir itself (not recursively) so PHP can rename the scripts folder inside it
chown "$WEB_USER":"$WEB_USER" "$WEBROOT"
for f in index.php viewer.php globalVariables.php; do
    [[ -f "$WEBROOT/$f" ]] && chown "$WEB_USER":"$WEB_USER" "$WEBROOT/$f"
done

# ── Done ──────────────────────────────────────────────────────────────────────
echo "[4/4] Done!"
echo ""
echo "  Open your browser and visit:"
echo "  http://your-server/$SCRIPTS_FOLDER/setup.php"
echo ""
echo "  After setup, your file browser will be at:"
echo "  http://your-server/"
echo ""
