#!/usr/bin/env bash
# @name        Waterfox: NVIDIA hardware video decoding
# @category    Browser
# @root        no
# @description Turns on VA-API hardware video decoding in every Waterfox profile
#              on NVIDIA GPUs, so YouTube serves AV1 instead of VP9. Needs the
#              libva-nvidia-driver package. Restart Waterfox and log out/in after.
#
# Writes a marked block to user.js in each profile (re-running replaces it) and
# sets LIBVA_DRIVER_NAME / NVD_BACKEND in ~/.config/environment.d/.
#
# To undo: delete the "linux-tweaks" block from user.js, set the two prefs back
# in about:config, and remove ~/.config/environment.d/90-nvidia-vaapi.conf.

set -euo pipefail

MARK_BEGIN='// >>> linux-tweaks: waterfox-nvidia-hw-video >>>'
MARK_END='// <<< linux-tweaks: waterfox-nvidia-hw-video <<<'
ENV_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/environment.d/90-nvidia-vaapi.conf"

say()  { printf '  %s\n' "$*"; }
fail() { printf '  ✗ %s\n' "$*" >&2; exit 1; }

# ── Checks ───────────────────────────────────────────────────────────────────

if [[ ! -e /proc/driver/nvidia/version ]] && ! lspci 2>/dev/null | grep -qiE '(vga|3d|display).*nvidia'; then
    fail "No NVIDIA GPU found — this tweak is NVIDIA-only."
fi

has_vaapi_driver() {
    local d
    for d in /usr/lib/dri /usr/lib64/dri /usr/lib/x86_64-linux-gnu/dri /usr/lib/aarch64-linux-gnu/dri; do
        [[ -e $d/nvidia_drv_video.so ]] && return 0
    done
    return 1
}

if ! has_vaapi_driver; then
    fail "The NVIDIA VA-API driver (nvidia_drv_video.so) isn't installed. Install it, then run this again:
      Arch / CachyOS:  sudo pacman -S libva-nvidia-driver
      Fedora:          sudo dnf install libva-nvidia-driver
      Debian / Ubuntu: sudo apt install nvidia-vaapi-driver"
fi

# ── Profiles ─────────────────────────────────────────────────────────────────

profiles=()
for base in "$HOME/.waterfox" "${XDG_CONFIG_HOME:-$HOME/.config}/waterfox" "$HOME/.var/app/net.waterfox.waterfox/.waterfox"; do
    for dir in "$base"/*/; do
        [[ -f $dir/prefs.js ]] && profiles+=("${dir%/}")
    done
done

(( ${#profiles[@]} )) || fail "No Waterfox profiles found. Start Waterfox once, then run this again."

for dir in "${profiles[@]}"; do
    file=$dir/user.js
    tmp=$(mktemp)
    # keep everything except a previous copy of our block
    if [[ -f $file ]]; then
        awk -v b="$MARK_BEGIN" -v e="$MARK_END" '$0 == b { skip = 1; next } $0 == e { skip = 0; next } !skip' "$file" > "$tmp"
    fi
    {
        printf '%s\n' "$MARK_BEGIN"
        printf '%s\n' 'user_pref("media.ffmpeg.vaapi.enabled", true);'
        printf '%s\n' 'user_pref("media.hardware-video-decoding.force-enabled", true);'
        printf '%s\n' "$MARK_END"
    } >> "$tmp"
    cat "$tmp" > "$file"
    rm -f "$tmp"
    say "✓ ${dir##*/}/user.js"
done

# ── Environment ──────────────────────────────────────────────────────────────

mkdir -p "${ENV_FILE%/*}"
printf '%s\n' \
    '# Added by linux-tweaks (waterfox-nvidia-hw-video): VA-API on NVIDIA' \
    'LIBVA_DRIVER_NAME=nvidia' \
    'NVD_BACKEND=direct' > "$ENV_FILE"
say "✓ ${ENV_FILE/#$HOME/\~}"

say ""
if pgrep -x "waterfox(-bin)?" >/dev/null 2>&1; then
    say "Waterfox is running — restart it to apply the settings."
fi
say "Log out and back in so the environment variables load."
say "Check: play a YouTube video → right-click → Stats for nerds → Codecs should say av01."
