#!/bin/bash
# IGProxy interactive installer UI.
# All rendering goes to stderr so command substitutions keep stdout clean.

IG_UI_TTY="${IG_UI_TTY:-}"
IG_UI_COLOR="${IG_UI_COLOR:-1}"
IG_UI_UNICODE="${IG_UI_UNICODE:-1}"

ig_ui_init() {
    if [ -z "$IG_UI_TTY" ]; then
        if [ -t 0 ]; then
            IG_UI_TTY="/dev/stdin"
        elif [ -r /dev/tty ] 2>/dev/null; then
            IG_UI_TTY="/dev/tty"
        else
            IG_UI_TTY="/dev/stdin"
        fi
    fi
    if [ ! -t 1 ] && [ ! -t 2 ]; then
        IG_UI_COLOR=0
    fi
    case "${TERM:-}" in
        ""|dumb) IG_UI_COLOR=0 ;;
    esac
    case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
        *UTF-8*|*utf8*|*UTF8*) ;;
        *) IG_UI_UNICODE=0 ;;
    esac

    if [ "$IG_UI_COLOR" = "1" ]; then
        IG_UI_RESET=$'\033[0m'
        IG_UI_BOLD=$'\033[1m'
        IG_UI_DIM=$'\033[2m'
        IG_UI_BLUE=$'\033[38;5;75m'
        IG_UI_CYAN=$'\033[38;5;81m'
        IG_UI_GREEN=$'\033[38;5;78m'
        IG_UI_YELLOW=$'\033[38;5;221m'
        IG_UI_RED=$'\033[38;5;203m'
        IG_UI_WHITE=$'\033[38;5;255m'
        IG_UI_MUTED=$'\033[38;5;109m'
        IG_UI_PANEL=$'\033[48;5;235m'
    else
        IG_UI_RESET=""
        IG_UI_BOLD=""
        IG_UI_DIM=""
        IG_UI_BLUE=""
        IG_UI_CYAN=""
        IG_UI_GREEN=""
        IG_UI_YELLOW=""
        IG_UI_RED=""
        IG_UI_WHITE=""
        IG_UI_MUTED=""
        IG_UI_PANEL=""
    fi
}

ig_ui_symbol() {
    local unicode="$1" ascii="$2"
    if [ "$IG_UI_UNICODE" = "1" ]; then
        printf '%s' "$unicode"
    else
        printf '%s' "$ascii"
    fi
}

ig_ui_rule() {
    local width="${1:-62}" ch line="" i
    ch=$(ig_ui_symbol "─" "-")
    for ((i = 0; i < width; i++)); do line+="$ch"; done
    printf '  %s%s%s\n' "$IG_UI_DIM" "$line" "$IG_UI_RESET" >&2
}

ig_ui_logo() {
    local role="${1:-Умная установка}" tl tr bl br vertical diamond padding
    tl=$(ig_ui_symbol "╭" "+")
    tr=$(ig_ui_symbol "╮" "+")
    bl=$(ig_ui_symbol "╰" "+")
    br=$(ig_ui_symbol "╯" "+")
    vertical=$(ig_ui_symbol "│" "|")
    diamond=$(ig_ui_symbol "◆" "*")
    padding=$((58 - ${#role}))
    [ "$padding" -lt 1 ] && padding=1
    printf '\n' >&2
    printf '  %s%s%s%s%s%s\n' "$IG_UI_BLUE" "$IG_UI_BOLD" "$tl" "$(printf '%60s' '' | tr ' ' '-')" "$tr" "$IG_UI_RESET" >&2
    printf '  %s%s%s%s  %s%s IGProxy%s  %sединый центр Telegram MTProxy%s                 %s%s%s%s\n' \
        "$IG_UI_BLUE" "$IG_UI_BOLD" "$IG_UI_RESET" \
        "$vertical" "$IG_UI_WHITE" "$diamond" "$IG_UI_RESET" "$IG_UI_MUTED" "$IG_UI_RESET" \
        "$IG_UI_BLUE" "$IG_UI_BOLD" "$vertical" "$IG_UI_RESET" >&2
    printf '  %s%s%s%s  %s%s%s%*s%s%s%s%s\n' \
        "$IG_UI_BLUE" "$IG_UI_BOLD" "$vertical" "$IG_UI_RESET" \
        "$IG_UI_CYAN" "$role" "$IG_UI_RESET" \
        "$padding" "" "$IG_UI_BLUE" "$IG_UI_BOLD" "$vertical" "$IG_UI_RESET" >&2
    printf '  %s%s%s%s%s%s\n' "$IG_UI_BLUE" "$IG_UI_BOLD" "$bl" "$(printf '%60s' '' | tr ' ' '-')" "$br" "$IG_UI_RESET" >&2
}

ig_ui_stepper() {
    local current="$1"
    shift
    local total="$#" i=1 title mark color
    printf '\n  ' >&2
    for title in "$@"; do
        if [ "$i" -lt "$current" ]; then
            mark=$(ig_ui_symbol "●" "*")
            color="$IG_UI_GREEN"
        elif [ "$i" -eq "$current" ]; then
            mark=$(ig_ui_symbol "◆" ">")
            color="$IG_UI_CYAN"
        else
            mark=$(ig_ui_symbol "○" "o")
            color="$IG_UI_MUTED"
        fi
        printf '%s%s%s %s' "$color" "$mark" "$IG_UI_RESET" "$title" >&2
        [ "$i" -lt "$total" ] && printf '  %s%s%s  ' "$IG_UI_DIM" "$(ig_ui_symbol "━━" "--")" "$IG_UI_RESET" >&2
        i=$((i + 1))
    done
    printf '\n' >&2
}

ig_ui_heading() {
    local eyebrow="$1" title="$2" description="${3:-}"
    printf '\n  %s%s%s\n' "$IG_UI_CYAN" "$eyebrow" "$IG_UI_RESET" >&2
    printf '  %s%s%s\n' "$IG_UI_BOLD$IG_UI_WHITE" "$title" "$IG_UI_RESET" >&2
    [ -n "$description" ] && printf '  %s%s%s\n' "$IG_UI_MUTED" "$description" "$IG_UI_RESET" >&2
}

ig_ui_option() {
    local index="$1" title="$2" description="$3" badge="${4:-}"
    local open close bullet
    open=$(ig_ui_symbol "╭" "+")
    close=$(ig_ui_symbol "╰" "+")
    bullet=$(ig_ui_symbol "│" "|")
    printf '\n  %s%s─[%s%s%s]────────────────────────────────────────────────────%s\n' \
        "$IG_UI_BLUE" "$open" "$IG_UI_BOLD$IG_UI_WHITE" "$index" "$IG_UI_RESET$IG_UI_BLUE" "$IG_UI_RESET" >&2
    printf '  %s%s%s  %s%s%s' "$IG_UI_BLUE" "$bullet" "$IG_UI_RESET" "$IG_UI_BOLD" "$title" "$IG_UI_RESET" >&2
    [ -n "$badge" ] && printf '  %s%s%s' "$IG_UI_GREEN" "$badge" "$IG_UI_RESET" >&2
    printf '\n' >&2
    printf '  %s%s%s  %s%s%s\n' "$IG_UI_BLUE" "$bullet" "$IG_UI_RESET" "$IG_UI_MUTED" "$description" "$IG_UI_RESET" >&2
    printf '  %s%s──────────────────────────────────────────────────────────%s\n' "$IG_UI_BLUE" "$close" "$IG_UI_RESET" >&2
}

# Usage: ig_ui_select "Prompt" default_index "value|title|description|badge" ...
# Prints only the selected value to stdout.
ig_ui_select() {
    local prompt="$1" default_index="$2"
    shift 2
    local options=("$@") count="${#options[@]}" i=1 row value title description badge answer
    for row in "${options[@]}"; do
        IFS='|' read -r value title description badge <<< "$row"
        ig_ui_option "$i" "$title" "$description" "$badge"
        i=$((i + 1))
    done
    while true; do
        printf '\n  %s%s%s %s[%s]:%s ' \
            "$IG_UI_CYAN" "$(ig_ui_symbol "❯" ">")" "$IG_UI_RESET" \
            "$prompt" "$default_index" "$IG_UI_RESET" >&2
        IFS= read -r answer < "$IG_UI_TTY" || answer=""
        answer="${answer:-$default_index}"
        if [[ "$answer" =~ ^[0-9]+$ ]] && [ "$answer" -ge 1 ] && [ "$answer" -le "$count" ]; then
            IFS='|' read -r value title description badge <<< "${options[$((answer - 1))]}"
            printf '%s\n' "$value"
            return 0
        fi
        if [ "$answer" = "0" ] || [ "$answer" = "q" ] || [ "$answer" = "Q" ]; then
            return 1
        fi
        printf '  %s%s Выберите пункт от 1 до %s.%s\n' \
            "$IG_UI_YELLOW" "$(ig_ui_symbol "!" "!")" "$count" "$IG_UI_RESET" >&2
    done
}

ig_ui_status() {
    local state="$1" label="$2" detail="${3:-}" symbol color
    case "$state" in
        ok)
            symbol=$(ig_ui_symbol "✓" "OK")
            color="$IG_UI_GREEN"
            ;;
        warn)
            symbol=$(ig_ui_symbol "!" "!")
            color="$IG_UI_YELLOW"
            ;;
        error)
            symbol=$(ig_ui_symbol "×" "X")
            color="$IG_UI_RED"
            ;;
        active)
            symbol=$(ig_ui_symbol "◆" ">")
            color="$IG_UI_CYAN"
            ;;
        *)
            symbol=$(ig_ui_symbol "·" "-")
            color="$IG_UI_MUTED"
            ;;
    esac
    printf '  %s%s%s  %s%s%s' "$color" "$symbol" "$IG_UI_RESET" "$IG_UI_BOLD" "$label" "$IG_UI_RESET" >&2
    [ -n "$detail" ] && printf '  %s%s%s' "$IG_UI_MUTED" "$detail" "$IG_UI_RESET" >&2
    printf '\n' >&2
}

ig_ui_key_value() {
    local label="$1" value="$2"
    printf '  %s%-22s%s %s%s%s\n' "$IG_UI_MUTED" "$label" "$IG_UI_RESET" "$IG_UI_WHITE" "$value" "$IG_UI_RESET" >&2
}

ig_ui_note() {
    local text="$1"
    printf '\n  %s%s%s %s%s%s\n' \
        "$IG_UI_CYAN" "$(ig_ui_symbol "◇" "*")" "$IG_UI_RESET" \
        "$IG_UI_MUTED" "$text" "$IG_UI_RESET" >&2
}

ig_ui_success() {
    local title="$1" description="${2:-}"
    printf '\n  %s%s%s  %s%s%s\n' \
        "$IG_UI_GREEN" "$(ig_ui_symbol "✓" "OK")" "$IG_UI_RESET" \
        "$IG_UI_BOLD$IG_UI_WHITE" "$title" "$IG_UI_RESET" >&2
    [ -n "$description" ] && printf '     %s%s%s\n' "$IG_UI_MUTED" "$description" "$IG_UI_RESET" >&2
}

ig_ui_init
