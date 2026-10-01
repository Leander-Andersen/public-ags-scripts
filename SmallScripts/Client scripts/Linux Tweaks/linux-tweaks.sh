#!/usr/bin/env bash
#
# Linux Tweaks — a cute interactive menu that indexes the tweak scripts in
# tweaks/, lets you pick some with the keyboard or mouse, then downloads and
# runs them one by one.
#
# Run from the script server:
#   bash <(curl -fsSL "https://<SCRIPT_DOMAIN>/<SCRIPT_FOLDER>/SmallScripts/Client%20scripts/Linux%20Tweaks/linux-tweaks.sh")
#
# Run from a local clone (reads ./tweaks directly, no server needed):
#   bash linux-tweaks.sh
#
# Set LINUX_TWEAKS_URL to point the menu at a different server folder.

set -uo pipefail

BASE_URL="${LINUX_TWEAKS_URL:-https://<SCRIPT_DOMAIN>/<SCRIPT_FOLDER>/SmallScripts/Client%20scripts/Linux%20Tweaks}"
SAFE_NAME='^[A-Za-z0-9._-]+\.sh$'
ESC=$'\e'

SCRIPT_DIR=''
if [[ -z ${LINUX_TWEAKS_URL:-} && -f ${BASH_SOURCE[0]:-} ]]; then
    SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
fi

MODE=''          # local | remote
WORK=''          # temp dir for downloaded tweaks
IN_TUI=0
SAVED_STTY=''

# Tweak index (parallel arrays) and menu state
declare -a T_FILE=() T_ROOT=() T_CAT=() T_NAME=() T_DESC=() SEL=()
declare -a ROW_KIND=() ROW_REF=() WRAPPED=()
CURSOR=1 TOP=0 LIST_H=0 LIST_Y0=3 W=0 IW=0 PX=1 LAST_SIZE='' MSG='' ACTION=''
BTN_Y=0 BTN_RUN_X1=0 BTN_RUN_X2=0 BTN_ALL_X1=0 BTN_ALL_X2=0 BTN_QUIT_X1=0 BTN_QUIT_X2=0
KEY='' MOUSE_B=0 MOUSE_X=0 MOUSE_Y=0 MOUSE_PRESS=0

# ── Look & feel (CutenessOverload palette) ────────────────────────────────────

setup_glyphs() {
    if [[ $(locale charmap 2>/dev/null) == UTF-8 ]]; then
        G_TL='╭' G_TR='╮' G_BL='╰' G_BR='╯' G_H='─' G_V='│' G_LT='├' G_RT='┤'
        G_HEART='♡' G_ON='♥' G_PTR='❯' G_FLOWER='✿' G_OK='✓' G_BAD='✗' G_DOT='·' G_ELL='…' G_ARROWS='↑↓'
    else
        G_TL='+' G_TR='+' G_BL='+' G_BR='+' G_H='-' G_V='|' G_LT='+' G_RT='+'
        G_HEART='<3' G_ON='*' G_PTR='>' G_FLOWER='*' G_OK='ok' G_BAD='x' G_DOT='-' G_ELL='.' G_ARROWS='up/down'
    fi
}

setup_colours() {
    local tc=0
    case ${COLORTERM:-} in truecolor|24bit) tc=1 ;; esac

    # colour <38=fg|48=bg> r g b <256-colour fallback>
    colour() {
        if (( tc )); then printf '%s[%s;2;%s;%s;%sm' "$ESC" "$1" "$2" "$3" "$4"
        else printf '%s[%s;5;%sm' "$ESC" "$1" "$5"; fi
    }

    C_PANEL=$(colour 48 255 213 216 224)   # #FFD5D8 light bubblegum — panel
    C_HEAD=$(colour 48 255 178 183 217)    # #FFB2B7 bubblegum — header / chips
    C_FOCUS=$(colour 48 255 143 154 211)   # #FF8F9A — highlighted row
    C_BTN=$(colour 48 200 50 90 161)       # #C8325A — run button
    C_TEXT=$(colour 38 80 25 40 52)        # #501928 plum text
    C_ACCENT=$(colour 38 200 50 90 161)    # #C8325A raspberry accent
    C_MUTED=$(colour 38 140 80 100 95)     # #8C5064
    C_LIGHT=$(colour 38 255 213 216 224)   # text on the run button
    C_GOOD=$(colour 38 60 150 90 71)
    C_BAD=$(colour 38 200 50 70 160)
    C_WARN=$(colour 38 200 130 50 172)
    C_BORDER=$C_ACCENT
    BOLD="${ESC}[1m" NOBOLD="${ESC}[22m" RESET="${ESC}[0m"
}

# ── Small helpers ─────────────────────────────────────────────────────────────

err()  { printf '  %s%s%s %s\n' "$C_BAD" "$G_BAD" "$RESET" "$*" >&2; }
chip() { printf '\n%s%s%s %s %s\n\n' "$C_HEAD" "$C_TEXT" "$BOLD" "$1" "$RESET"; }

trim() {
    local s=$1
    s=${s#"${s%%[![:space:]]*}"}
    REPLY=${s%"${s##*[![:space:]]}"}
}

repeat() { local s; printf -v s '%*s' "$2" ''; REPLY=${s// /$1}; }

fit() {  # text width -> REPLY truncated to width
    local s=$1 n=$2
    (( n < 1 )) && { REPLY=''; return; }
    (( ${#s} > n )) && s="${s:0:n-1}${G_ELL:0:1}"
    REPLY=$s
}

wrap() {  # text width -> WRAPPED lines
    local line='' word
    local -a words
    WRAPPED=()
    read -ra words <<<"$1"
    for word in "${words[@]}"; do
        if [[ -z $line ]]; then line=$word
        elif (( ${#line} + 1 + ${#word} <= $2 )); then line+=" $word"
        else WRAPPED+=("$line"); line=$word; fi
    done
    [[ -n $line ]] && WRAPPED+=("$line")
}

usage() {
    cat <<EOF
Linux Tweaks — pick tweak scripts from a cute menu and run them.

Usage: bash linux-tweaks.sh

Controls:
  up/down, j/k     move              space     select / unselect
  a                select all         enter     run selected
  home/end, g/G    jump               q, esc    quit
  mouse            click a tweak to select it, click a category to select
                   the whole category, scroll to move, click the buttons

Tweaks are read from ./tweaks when run from a clone, otherwise from:
  $BASE_URL
EOF
}

# ── Index ─────────────────────────────────────────────────────────────────────
# Index line format (same as list.php): file \t root \t category \t name \t description

parse_header() {
    local f=$1 file line key='' name='' cat='' root='' desc='' w
    local re='^#[[:space:]]*@([a-z]+)[[:space:]]+(.*)$'
    local cont='^#[[:space:]]+([^[:space:]].*)$'
    file=${f##*/}

    while IFS= read -r line || [[ -n $line ]]; do
        line=${line%$'\r'}
        [[ $line == '#!'* ]] && continue
        [[ $line == '#'* ]] || break
        if [[ $line =~ $re ]]; then
            key=${BASH_REMATCH[1]}
            trim "${BASH_REMATCH[2]}"
            case $key in
                name) name=$REPLY ;;
                description) desc=$REPLY ;;
                category) cat=$REPLY ;;
                root) root=$REPLY ;;
            esac
        elif [[ $key == description && $line =~ $cont ]]; then
            trim "${BASH_REMATCH[1]}"
            desc+=" $REPLY"
        else
            key=''
        fi
    done < "$f"

    read -r w _ <<<"${root,,}"
    case $w in yes|true|1) root=yes ;; *) root=no ;; esac
    printf '%s\t%s\t%s\t%s\t%s\n' "$file" "$root" "${cat//$'\t'/ }" "${name//$'\t'/ }" "${desc//$'\t'/ }"
}

local_index() {
    local f
    for f in "$SCRIPT_DIR"/tweaks/*.sh; do
        [[ -f $f ]] && parse_header "$f"
    done | sort -t $'\t' -k3,3f -k4,4f
}

load_index() {
    local data file root cat name desc
    if [[ -n $SCRIPT_DIR && -d $SCRIPT_DIR/tweaks ]]; then
        MODE=local
        data=$(local_index)
    else
        MODE=remote
        if [[ $BASE_URL == *'<SCRIPT_'* ]]; then
            err "The script server isn't set up yet (run setup.php), or set LINUX_TWEAKS_URL."
            return 1
        fi
        command -v curl >/dev/null || { err "curl is needed to download tweaks."; return 1; }
        printf '  %s%s%s fetching the tweak list%s\n' "$C_ACCENT" "$G_HEART" "$RESET" "$G_ELL"
        data=$(curl -fsSL --max-time 20 -- "$BASE_URL/list.php") || {
            err "Couldn't fetch $BASE_URL/list.php"
            return 1
        }
    fi

    while IFS=$'\t' read -r file root cat name desc; do
        [[ $file =~ $SAFE_NAME ]] || continue
        T_FILE+=("$file")
        T_ROOT+=("$root")
        T_CAT+=("${cat:-Other}")
        T_NAME+=("${name:-${file%.sh}}")
        T_DESC+=("$desc")
        SEL+=(0)
    done <<<"$data"

    (( ${#T_FILE[@]} )) || { err "No tweaks found."; return 1; }
}

build_rows() {  # category heading rows + one row per tweak
    local i last=$'\x01'
    for i in "${!T_FILE[@]}"; do
        if [[ ${T_CAT[i]} != "$last" ]]; then
            ROW_KIND+=(h); ROW_REF+=("$i"); last=${T_CAT[i]}
        fi
        ROW_KIND+=(i); ROW_REF+=("$i")
    done
}

# ── Selection ─────────────────────────────────────────────────────────────────

count_selected() {
    local i n=0
    for i in "${SEL[@]}"; do (( n += i )); done
    REPLY=$n
}

toggle() { SEL[$1]=$(( 1 - SEL[$1] )); }

toggle_where() {  # category|'' — select all (in category) unless all are already selected
    local i all=1
    for i in "${!T_FILE[@]}"; do
        [[ -z $1 || ${T_CAT[i]} == "$1" ]] && (( ! SEL[i] )) && all=0
    done
    for i in "${!T_FILE[@]}"; do
        [[ -z $1 || ${T_CAT[i]} == "$1" ]] && SEL[i]=$(( 1 - all ))
    done
}

move() {  # step N tweak rows up (negative) or down, skipping category headings
    local r=$CURSOR nr step=1 left=$1 n=${#ROW_KIND[@]}
    (( left < 0 )) && { step=-1; left=$(( -left )); }
    while (( left > 0 )); do
        nr=$(( r + step ))
        while (( nr >= 0 && nr < n )) && [[ ${ROW_KIND[nr]} == h ]]; do nr=$(( nr + step )); done
        (( nr >= 0 && nr < n )) || break
        r=$nr
        left=$(( left - 1 ))
    done
    CURSOR=$r
}

# ── Drawing ───────────────────────────────────────────────────────────────────

BUF='' _row='' _len=0

row_begin() { _row=''; _len=0; }
seg() { _row+="$1$2"; _len=$(( _len + ${#2} )); }   # colour, text

row_end() {  # y bg — pad to the inner width and add the side borders
    local pad=$(( IW - _len ))
    (( pad < 0 )) && pad=0
    printf -v REPLY '%*s' "$pad" ''
    BUF+="${ESC}[$1;${PX}H$2${C_BORDER}${G_V}${_row}$2${REPLY}${C_BORDER}${G_V}${RESET}"
}

border_row() {  # y left right [label]
    local label=${4:-}
    repeat "$G_H" $(( W - 3 - ${#label} ))
    BUF+="${ESC}[$1;${PX}H${C_PANEL}${C_BORDER}$2${REPLY}${C_MUTED}${label}${C_BORDER}${G_H}$3${RESET}"
}

render() {
    local size lines cols nrows k r i y bg ptr box tag title info nsel lead
    size=$(stty size 2>/dev/null) || size='24 80'
    read -r lines cols <<<"$size"
    BUF=''
    if [[ $size != "$LAST_SIZE" ]]; then BUF+="${ESC}[2J"; LAST_SIZE=$size; fi

    if (( cols < 44 || lines < 14 )); then
        LIST_H=0 BTN_Y=0
        BUF+="${ESC}[H${C_ACCENT}${G_HEART} make the terminal a little bigger ${G_HEART}${RESET}"
        printf '%s' "$BUF"
        return
    fi

    W=$(( cols > 80 ? 78 : cols - 2 ))
    IW=$(( W - 2 ))
    PX=$(( (cols - W) / 2 + 1 ))
    nrows=${#ROW_KIND[@]}
    LIST_H=$(( lines - 12 ))
    (( LIST_H > nrows )) && LIST_H=$nrows

    # keep the cursor — and its category heading — on screen
    (( CURSOR < TOP )) && TOP=$CURSOR
    (( CURSOR >= TOP + LIST_H )) && TOP=$(( CURSOR - LIST_H + 1 ))
    if (( TOP == CURSOR && TOP > 0 )) && [[ ${ROW_KIND[TOP-1]} == h ]]; then TOP=$(( TOP - 1 )); fi

    count_selected; nsel=$REPLY

    # title bar
    title=" $G_HEART Linux Tweaks $G_HEART "
    info=" ${#T_FILE[@]} tweak$( (( ${#T_FILE[@]} > 1 )) && echo s) $G_DOT $nsel selected "
    (( W - 4 - ${#title} - ${#info} < 1 )) && info=''
    repeat "$G_H" $(( W - 4 - ${#title} - ${#info} ))
    BUF+="${ESC}[1;${PX}H${C_HEAD}${C_BORDER}${G_TL}${G_H}${C_TEXT}${BOLD}${title}${NOBOLD}${C_BORDER}${REPLY}${C_TEXT}${info}${C_BORDER}${G_H}${G_TR}${RESET}"

    row_begin
    if [[ $MODE == local ]]; then info='local clone'; else info=${BASE_URL#*://}; info=${info%%/*}; fi
    fit "pick some tweaks and press enter $G_DOT from $info" $(( IW - 3 ))
    seg "$C_MUTED" " $G_FLOWER $REPLY"
    row_end 2 "$C_PANEL"

    # tweak list
    for (( k = 0; k < LIST_H; k++ )); do
        r=$(( TOP + k )); y=$(( LIST_Y0 + k ))
        row_begin
        i=${ROW_REF[r]}
        if [[ ${ROW_KIND[r]} == h ]]; then
            seg "$C_ACCENT$BOLD" " $G_FLOWER ${T_CAT[i]}"
            seg "$NOBOLD" ''
            row_end "$y" "$C_PANEL"
            continue
        fi
        bg=$C_PANEL ptr=' ' box=' ' tag=''
        (( r == CURSOR )) && { bg=$C_FOCUS; ptr=$G_PTR; }
        (( SEL[i] )) && box=$G_ON
        [[ ${T_ROOT[i]} == yes ]] && tag='sudo '
        seg "$C_ACCENT$BOLD" "   $ptr "
        seg "$C_TEXT$NOBOLD" '['
        seg "$C_ACCENT" "$box"
        seg "$C_TEXT" '] '
        fit "${T_NAME[i]}" $(( IW - _len - ${#tag} - 1 ))
        if (( r == CURSOR )); then seg "$C_TEXT$BOLD" "$REPLY"; else seg "$C_TEXT" "$REPLY"; fi
        printf -v REPLY '%*s' $(( IW - _len - ${#tag} )) ''
        seg "$NOBOLD" "$REPLY"
        seg "$C_MUTED" "$tag"
        row_end "$y" "$bg"
    done
    y=$(( LIST_Y0 + LIST_H ))

    info=''
    (( nrows > LIST_H )) && info=" $(( TOP + 1 ))-$(( TOP + LIST_H )) of $nrows "
    border_row "$y" "$G_LT" "$G_RT" "$info"

    # description of the highlighted tweak
    i=${ROW_REF[CURSOR]}
    wrap "${T_DESC[i]:-No description.}" $(( IW - 4 ))
    if (( ${#WRAPPED[@]} > 3 )); then fit "${WRAPPED[2]} ${WRAPPED[3]}" $(( IW - 4 )); WRAPPED[2]=$REPLY; fi
    for k in 0 1 2; do
        row_begin
        seg "$C_TEXT" "  ${WRAPPED[k]:-}"
        row_end $(( y + 1 + k )) "$C_PANEL"
    done
    row_begin
    seg "$C_MUTED" "  tweaks/${T_FILE[i]}"
    [[ ${T_ROOT[i]} == yes ]] && seg "$C_WARN" " $G_DOT runs with sudo"
    row_end $(( y + 4 )) "$C_PANEL"
    y=$(( y + 5 ))
    border_row "$y" "$G_LT" "$G_RT"

    # buttons
    local b_run=" $G_ON Run selected ($nsel) " b_all=' Select all ' b_quit=' Quit '
    BTN_Y=$(( y + 1 ))
    lead=$(( (IW - ${#b_run} - ${#b_all} - ${#b_quit} - 6) / 2 ))
    BTN_RUN_X1=$(( PX + 1 + lead ));               BTN_RUN_X2=$(( BTN_RUN_X1 + ${#b_run} - 1 ))
    BTN_ALL_X1=$(( BTN_RUN_X2 + 4 ));              BTN_ALL_X2=$(( BTN_ALL_X1 + ${#b_all} - 1 ))
    BTN_QUIT_X1=$(( BTN_ALL_X2 + 4 ));             BTN_QUIT_X2=$(( BTN_QUIT_X1 + ${#b_quit} - 1 ))
    row_begin
    printf -v REPLY '%*s' "$lead" ''
    seg '' "$REPLY"
    seg "$C_BTN$C_LIGHT$BOLD" "$b_run"
    seg "$C_PANEL$NOBOLD" '   '
    seg "$C_HEAD$C_TEXT" "$b_all"
    seg "$C_PANEL" '   '
    seg "$C_HEAD$C_TEXT" "$b_quit"
    seg "$C_PANEL" ''
    row_end "$BTN_Y" "$C_PANEL"

    # key hints, or a one-off message
    row_begin
    if [[ -n $MSG ]]; then
        info=$MSG; MSG=''
        lead=$(( (IW - ${#info}) / 2 )); (( lead < 0 )) && lead=0
        printf -v REPLY '%*s' "$lead" ''
        seg "$C_BAD$BOLD" "$REPLY$info"
        seg "$NOBOLD" ''
    else
        fit "$G_ARROWS move $G_DOT space pick $G_DOT a all $G_DOT enter run $G_DOT q quit $G_DOT mouse works too" "$IW"
        info=$REPLY
        lead=$(( (IW - ${#info}) / 2 )); (( lead < 0 )) && lead=0
        printf -v REPLY '%*s' "$lead" ''
        seg "$C_MUTED" "$REPLY$info"
    fi
    row_end $(( BTN_Y + 1 )) "$C_PANEL"
    border_row $(( BTN_Y + 2 )) "$G_BL" "$G_BR"

    printf '%s' "$BUF"
}

# ── Input ─────────────────────────────────────────────────────────────────────

read_key() {  # sets KEY; returns 1 on timeout
    local k='' c='' s='' rc=0
    KEY=''
    IFS= read -rsn1 -t 0.5 k || rc=$?
    (( rc > 128 )) && return 1
    (( rc != 0 )) && { KEY=q; return 0; }

    case $k in
        '') KEY=enter ;;
        ' ') KEY=space ;;
        "$ESC")
            IFS= read -rsn1 -t 0.05 c || { KEY=esc; return 0; }
            [[ $c == '[' || $c == O ]] || { KEY=esc; return 0; }
            IFS= read -rsn1 -t 0.05 c || { KEY=esc; return 0; }
            case $c in
                A) KEY=up ;;
                B) KEY=down ;;
                H) KEY=home ;;
                F) KEY=end ;;
                [1-8])  # ESC [ n ~  (home/end/pgup/pgdn)
                    s=$c
                    while IFS= read -rsn1 -t 0.05 c && [[ $c != '~' ]]; do s+=$c; done
                    case $s in 1|7) KEY=home ;; 4|8) KEY=end ;; 5) KEY=pgup ;; 6) KEY=pgdn ;; *) KEY=other ;; esac
                    ;;
                '<')    # SGR mouse: ESC [ < button ; x ; y (M=press, m=release)
                    while IFS= read -rsn1 -t 0.05 c; do
                        s+=$c
                        [[ $c == [Mm] ]] && break
                    done
                    KEY=mouse
                    MOUSE_PRESS=0
                    [[ $s == *M ]] && MOUSE_PRESS=1
                    IFS=';' read -r MOUSE_B MOUSE_X MOUSE_Y <<<"${s%[Mm]}"
                    ;;
                *) KEY=other ;;
            esac
            ;;
        *) KEY=$k ;;
    esac
}

on_mouse() {
    local r
    (( MOUSE_PRESS )) || return 0
    case $MOUSE_B in
        64) move -1; return 0 ;;   # wheel up
        65) move 1;  return 0 ;;   # wheel down
        0) ;;                      # left click
        *) return 0 ;;
    esac

    if (( LIST_H > 0 && MOUSE_Y >= LIST_Y0 && MOUSE_Y < LIST_Y0 + LIST_H && MOUSE_X > PX && MOUSE_X < PX + W - 1 )); then
        r=$(( TOP + MOUSE_Y - LIST_Y0 ))
        if [[ ${ROW_KIND[r]} == h ]]; then
            toggle_where "${T_CAT[${ROW_REF[r]}]}"
        else
            CURSOR=$r
            toggle "${ROW_REF[r]}"
        fi
    elif (( BTN_Y > 0 && MOUSE_Y == BTN_Y )); then
        if   (( MOUSE_X >= BTN_RUN_X1  && MOUSE_X <= BTN_RUN_X2 ));  then ACTION=run
        elif (( MOUSE_X >= BTN_ALL_X1  && MOUSE_X <= BTN_ALL_X2 ));  then toggle_where ''
        elif (( MOUSE_X >= BTN_QUIT_X1 && MOUSE_X <= BTN_QUIT_X2 )); then ACTION=quit
        fi
    fi
}

# ── Terminal setup ────────────────────────────────────────────────────────────

tui_enter() {
    SAVED_STTY=$(stty -g)
    stty -echo
    IN_TUI=1
    # alternate screen, hide cursor, mouse clicks + SGR coordinates
    printf '%s' "${ESC}[?1049h${ESC}[?25l${ESC}[?1000h${ESC}[?1006h"
}

tui_leave() {
    (( IN_TUI )) || return 0
    IN_TUI=0
    printf '%s' "${ESC}[?1006l${ESC}[?1000l${ESC}[?25h${ESC}[?1049l"
    [[ -n $SAVED_STTY ]] && stty "$SAVED_STTY"
}

cleanup() {
    tui_leave
    [[ -n $WORK ]] && rm -rf -- "$WORK"
}

tui() {  # returns 0 to run the selection, 1 to quit
    tui_enter
    while :; do
        render
        ACTION=''
        read_key || continue
        case $KEY in
            up|k)     move -1 ;;
            down|j)   move 1 ;;
            pgup)     move $(( -LIST_H )) ;;
            pgdn)     move "$LIST_H" ;;
            home|g)   CURSOR=0; move 1 ;;
            end|G)    CURSOR=$(( ${#ROW_KIND[@]} - 1 )) ;;
            space)    toggle "${ROW_REF[CURSOR]}" ;;
            a|A)      toggle_where '' ;;
            enter)    ACTION=run ;;
            q|Q|esc)  ACTION=quit ;;
            mouse)    on_mouse ;;
        esac
        case $ACTION in
            quit) tui_leave; return 1 ;;
            run)
                count_selected
                if (( REPLY > 0 )); then tui_leave; return 0; fi
                MSG="pick at least one tweak first $G_HEART"
                ;;
        esac
    done
}

# ── Running ───────────────────────────────────────────────────────────────────

fetch_tweak() {  # file dest
    if [[ $MODE == local ]]; then
        cp -- "$SCRIPT_DIR/tweaks/$1" "$2" || return 1
    else
        curl -fsSL --max-time 60 -o "$2" -- "$BASE_URL/tweaks/$1" || return 1
    fi
    [[ $(head -c 2 -- "$2") == '#!' ]] || { err "$1 doesn't look like a script."; return 1; }
}

run_selected() {
    local -a pick=() results=()
    local i n=0 total need_root=0 use_sudo=0 failed=0 ans rc dest

    for i in "${!T_FILE[@]}"; do (( SEL[i] )) && pick+=("$i"); done
    total=${#pick[@]}

    chip "$G_FLOWER Ready to run $total tweak$( (( total > 1 )) && echo s) $G_FLOWER"
    for i in "${pick[@]}"; do
        printf '  %s%s%s %s' "$C_ACCENT" "$G_ON" "$RESET" "${T_NAME[i]}"
        if [[ ${T_ROOT[i]} == yes ]]; then
            need_root=1
            printf ' %s(sudo)%s' "$C_WARN" "$RESET"
        fi
        printf '\n'
    done
    printf '\n  Go ahead? [y/N] '
    read -r ans || ans=''
    if [[ $ans != [yY]* ]]; then
        printf '  nothing ran %s\n' "$G_HEART"
        return 0
    fi

    if (( need_root && EUID != 0 )); then
        command -v sudo >/dev/null || { err "Some tweaks need root, but sudo isn't installed."; return 1; }
        sudo -v || { err "sudo failed — nothing ran."; return 1; }
        use_sudo=1
    fi

    WORK=$(mktemp -d) || { err "Couldn't create a temp folder."; return 1; }

    for i in "${pick[@]}"; do
        n=$(( n + 1 ))
        dest=$WORK/${T_FILE[i]}
        chip "[$n/$total] ${T_NAME[i]}"

        if ! fetch_tweak "${T_FILE[i]}" "$dest"; then
            results+=("${C_BAD}${G_BAD}${RESET} ${T_NAME[i]} ${C_MUTED}(download failed)${RESET}")
            failed=$(( failed + 1 ))
            continue
        fi

        rc=0
        if [[ ${T_ROOT[i]} == yes ]] && (( use_sudo )); then
            sudo bash "$dest" || rc=$?
        else
            bash "$dest" || rc=$?
        fi

        if (( rc == 0 )); then
            results+=("${C_GOOD}${G_OK}${RESET} ${T_NAME[i]}")
        else
            results+=("${C_BAD}${G_BAD}${RESET} ${T_NAME[i]} ${C_MUTED}(exit $rc)${RESET}")
            failed=$(( failed + 1 ))
        fi
    done

    chip "$G_HEART All done $G_HEART"
    printf '  %s\n' "${results[@]}"
    printf '\n'
    (( failed == 0 ))
}

main() {
    case ${1:-} in -h|--help) setup_glyphs; usage; return 0 ;; esac

    (( BASH_VERSINFO[0] >= 4 )) || { echo "Linux Tweaks needs bash 4 or newer." >&2; return 1; }

    # curl ... | bash leaves stdin on the pipe — read keys from the terminal instead
    if [[ ! -t 0 ]] && : </dev/tty 2>/dev/null; then exec </dev/tty; fi
    if [[ ! -t 0 || ! -t 1 ]]; then echo "Linux Tweaks needs an interactive terminal." >&2; return 1; fi

    setup_glyphs
    setup_colours
    trap cleanup EXIT
    trap 'exit 130' INT TERM

    load_index || return 1
    build_rows

    if ! tui; then
        printf '  bye %s\n' "$G_HEART"
        return 0
    fi
    run_selected
}

main "$@"; exit
