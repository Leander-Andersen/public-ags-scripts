# Linux Tweaks

A cute pink terminal menu for Linux tweaks. It finds every tweak script in `tweaks/`, shows them as a checklist with a short description, and downloads and runs the ones you pick. Works with both keyboard and mouse.

Adding a tweak is just dropping a new `.sh` file into `tweaks/` — the menu picks it up automatically.

## Usage

Run in a terminal (**not** as root — tweaks that need root ask for `sudo` themselves):

```bash
bash <(curl -fsSL "https://<SCRIPT_DOMAIN>/<SCRIPT_FOLDER>/SmallScripts/Client%20scripts/Linux%20Tweaks/linux-tweaks.sh")
```

Or from a clone of the repo, which reads `tweaks/` directly with no server involved:

```bash
bash linux-tweaks.sh
```

Requires bash 4+ and `curl`. Truecolor terminals get the full CutenessOverload palette; others fall back to the closest 256-colour pinks.

## Controls

| Key | Action |
|---|---|
| `↑` `↓` / `j` `k` | Move |
| `Space` | Select / unselect the highlighted tweak |
| `a` | Select all (press again to clear) |
| `Enter` | Run the selected tweaks |
| `Home` `End` / `g` `G`, `PgUp` `PgDn` | Jump |
| `q` / `Esc` | Quit |
| Mouse | Click a tweak to select it, click a category heading to select the whole category, scroll to move, click **Run selected** / **Select all** / **Quit** |

The panel at the bottom shows the description of the highlighted tweak, its file name, and whether it runs with `sudo`.

## What it does

| Step | Detail |
|---|---|
| Index | Fetches `list.php`, which reads the header of every script in `tweaks/` and returns the list. From a local clone, it reads the headers itself. |
| Pick | Shows the interactive checklist, grouped by category. |
| Confirm | Lists what will run and asks before doing anything. Asks for `sudo` once, up front, only if a selected tweak needs root. |
| Run | Downloads each selected tweak to a temp folder and runs it, one at a time. |
| Summary | Shows ✓ / ✗ for each tweak and deletes the temp folder. Exits non-zero if any tweak failed. |

## Adding a tweak

Create `tweaks/<name>.sh` starting with a header like this:

```bash
#!/usr/bin/env bash
# @name        Waterfox: NVIDIA hardware video decoding
# @category    Browser
# @root        no
# @description Turns on VA-API hardware video decoding in every Waterfox profile
#              on NVIDIA GPUs, so YouTube serves AV1 instead of VP9.
#
# Anything after a blank "#" line is a normal comment and isn't shown in the menu.
```

| Field | Required | Meaning |
|---|---|---|
| `@name` | No (defaults to the file name) | Title shown in the list |
| `@category` | No (defaults to `Other`) | Heading the tweak is grouped under |
| `@root` | No (defaults to `no`) | `yes` runs the script with `sudo` |
| `@description` | No | Shown in the description panel. Continue it on following `#` lines indented with spaces; a blank `#` line ends it |

Rules for tweak scripts:

- File names may only contain letters, numbers, `.`, `_` and `-`, and must end in `.sh`. Others are ignored.
- Run as the normal user unless `@root yes`. Exit non-zero on failure so the summary shows ✗.
- Make them safe to run twice (replace your own changes instead of appending duplicates).
- They must pass ShellCheck — CI checks every `.sh` in the repo.

## Available tweaks

| Tweak | Category | Root | What it does |
|---|---|---|---|
| [Waterfox: NVIDIA hardware video decoding](tweaks/waterfox-nvidia-hw-video.sh) | Browser | No | Enables VA-API hardware decoding on NVIDIA in every Waterfox profile (`user.js`) and sets `LIBVA_DRIVER_NAME` / `NVD_BACKEND`, so YouTube serves AV1. |

## Configuration

`setup.php` fills in the server URL inside `linux-tweaks.sh` automatically. To point the menu somewhere else (e.g. a test server), set `LINUX_TWEAKS_URL` to the folder that contains `list.php`:

```bash
LINUX_TWEAKS_URL="https://example.com/scripts/SmallScripts/Client%20scripts/Linux%20Tweaks" bash linux-tweaks.sh
```
