#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# AGS Script Library — one-command installer
#
# Usage (run as root or with sudo):
#   sudo bash install.sh
#
# Optional arguments:
#   --dest  /path/to/webroot/folder   (default: /var/www/html/public-ags-scripts)
#   --user  www-data                  (default: auto-detected web server user)
#   --branch main                     (default: main)
# ─────────────────────────────────────────────────────────────────────────────
set -e

REPO_URL="https://github.com/Leander-Andersen/public-ags-scripts.git"
DEST="/var/www/html/public-ags-scripts"
BRANCH="main"
WEB_USER=""

# ── Parse arguments ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dest)   DEST="$2";    shift 2 ;;
        --user)   WEB_USER="$2"; shift 2 ;;
        --branch) BRANCH="$2";  shift 2 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

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
    echo "Please run as root: sudo bash install.sh"
    exit 1
fi

echo ""
echo "  Destination : $DEST"
echo "  Branch      : $BRANCH"
echo "  Web user    : $WEB_USER"
echo ""

# ── Clone or update ───────────────────────────────────────────────────────────
if [[ -d "$DEST/.git" ]]; then
    echo "[1/3] Repo already exists — pulling latest..."
    sudo -u "$WEB_USER" git -C "$DEST" fetch origin
    sudo -u "$WEB_USER" git -C "$DEST" reset --hard "origin/$BRANCH"
else
    echo "[1/3] Cloning repository..."
    # Clone as root then fix ownership, so git credentials work normally
    git clone --branch "$BRANCH" "$REPO_URL" "$DEST"
fi

# ── Set ownership ─────────────────────────────────────────────────────────────
echo "[2/3] Setting ownership to $WEB_USER..."
chown -R "$WEB_USER":"$WEB_USER" "$DEST"

# ── Done ──────────────────────────────────────────────────────────────────────
echo "[3/3] Done!"
echo ""
echo "  Now open your browser and visit:"
echo "  http://your-server/$(basename "$DEST")/setup.php"
echo ""
