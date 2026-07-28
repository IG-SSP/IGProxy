#!/bin/bash
# GoTelegram v2.5.0 — website templates catalog
# Pick from ~1800 templates, preview links, git sparse-checkout downloads,
# + custom git URL templates (user-supplied public repos)

CATALOG_FILE="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")/templates_catalog.json"
TEMPLATES_CACHE="${TEMPLATES_CACHE:-/var/cache/gotelegram/templates}"

# Custom git template limits
CUSTOM_GIT_MAX_SIZE_MB=100
CUSTOM_GIT_CLONE_TIMEOUT=90

# ── Catalog loading ────────────────────────────────────────────────────
load_catalog() {
    if [ ! -f "$CATALOG_FILE" ]; then
        if type tf &>/dev/null; then
            log_error "$(tf templates_catalog_not_found "$CATALOG_FILE")"
        else
            log_error "Templates catalog not found: $CATALOG_FILE"
        fi
        return 1
    fi
    return 0
}

# ── Categories ─────────────────────────────────────────────────────────
get_categories() {
    jq -r '.categories[] | "\(.id)|\(.name)|\(.icon)|\(.templates | length)"' "$CATALOG_FILE" 2>/dev/null
}

get_category_name() {
    local cat_id="$1"
    jq -r ".categories[] | select(.id == \"$cat_id\") | .name" "$CATALOG_FILE" 2>/dev/null
}

# ── Templates in a category ────────────────────────────────────────────
get_templates_by_category() {
    local cat_id="$1"
    jq -r ".categories[] | select(.id == \"$cat_id\") | .templates[] | \"\(.id)|\(.name)|\(.source)|\(.preview_url)\"" "$CATALOG_FILE" 2>/dev/null
}

# ── Template info ──────────────────────────────────────────────────────
get_template_info() {
    local tpl_id="$1"
    jq ".categories[].templates[] | select(.id == \"$tpl_id\")" "$CATALOG_FILE" 2>/dev/null
}

get_template_field() {
    local tpl_id="$1"
    local field="$2"
    jq -r ".categories[].templates[] | select(.id == \"$tpl_id\") | .$field" "$CATALOG_FILE" 2>/dev/null
}

# ── Interactive category picker (returns category id or special __custom_git__/__random__) ──
select_category() {
    load_catalog || return 1

    echo "" >&2
    echo -e "  ${BOLD}${WHITE}$(t templates_categories)${NC}" >&2
    echo -e "  ${DIM}$(printf '─%.0s' {1..55})${NC}" >&2

    # First item: custom git URL template
    printf "  ${CYAN}%2d)${NC} ${GREEN}%s${NC}\n" 1 "$(t templates_custom_git)" >&2

    local cats=()
    local i=2
    while IFS='|' read -r id name icon count; do
        [ "$count" -eq 0 ] && continue
        local emoji
        case "$icon" in
            briefcase)     emoji="🏢" ;;
            shopping-cart) emoji="🛒" ;;
            heart)         emoji="🏥" ;;
            book)          emoji="🎓" ;;
            palette)       emoji="📸" ;;
            home)          emoji="🏠" ;;
            utensils)      emoji="🍕" ;;
            rocket)        emoji="🎨" ;;
            chart-bar)     emoji="🔧" ;;
            *)             emoji="📄" ;;
        esac
        printf "  ${CYAN}%2d)${NC} ${emoji} %-30s ${DIM}$(tf templates_count_fmt "$count")${NC}\n" "$i" "$name" >&2
        cats+=("$id")
        ((i++))
    done < <(get_categories)

    printf "  ${CYAN}%2d)${NC} %s\n" "$i" "$(t templates_random)" >&2
    echo -e "  ${DIM}$(printf '─%.0s' {1..55})${NC}" >&2
    echo -ne "  ${WHITE}$(t choose):${NC} " >&2
    read -r choice

    if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
        log_error "$(t invalid_choice)"
        return 1
    fi

    # Custom git URL
    if [ "$choice" -eq 1 ]; then
        echo "__custom_git__"
        return 0
    fi

    # Random
    if [ "$choice" -eq "$i" ]; then
        local random_cat="${cats[$((RANDOM % ${#cats[@]}))]}"
        echo "$random_cat"
        return 0
    fi

    # Regular category (offset by 1 because item 1 is custom git)
    if [ "$choice" -ge 2 ] && [ "$choice" -lt "$i" ]; then
        echo "${cats[$((choice-2))]}"
        return 0
    fi

    log_error "$(t invalid_choice)"
    return 1
}

# ── Interactive template picker ────────────────────────────────────────
select_template() {
    local cat_id="$1"
    local cat_name
    cat_name=$(get_category_name "$cat_id")

    echo "" >&2
    echo -e "  ${BOLD}${WHITE}$(tf templates_list "$cat_name")${NC}" >&2
    echo -e "  ${DIM}$(printf '─%.0s' {1..60})${NC}" >&2

    local tpls=()
    local i=1
    while IFS='|' read -r id name source preview; do
        printf "  ${CYAN}%2d)${NC} %-30s ${DIM}[%s]${NC}\n" "$i" "$name" "$source" >&2
        tpls+=("$id")
        ((i++))
    done < <(get_templates_by_category "$cat_id")

    if [ ${#tpls[@]} -eq 0 ]; then
        log_info "$(t templates_cat_empty)"
        return 1
    fi

    echo -e "  ${DIM}$(printf '─%.0s' {1..60})${NC}" >&2
    echo -ne "  ${WHITE}$(t choose) (1-$((i-1))):${NC} " >&2
    read -r choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$i" ]; then
        local selected_id="${tpls[$((choice-1))]}"

        # Show preview
        show_template_preview "$selected_id" || return 1

        echo "$selected_id"
        return 0
    fi

    log_error "$(t invalid_choice)"
    return 1
}

# ── Template preview ───────────────────────────────────────────────────
show_template_preview() {
    local tpl_id="$1"
    local info
    info=$(get_template_info "$tpl_id")

    local name source preview_url repo_url description
    name=$(echo "$info" | jq -r '.name')
    source=$(echo "$info" | jq -r '.source')
    preview_url=$(echo "$info" | jq -r '.preview_url // empty')
    repo_url=$(echo "$info" | jq -r '.repo_url // empty')
    description=$(echo "$info" | jq -r '.description // "—"')

    echo "" >&2
    echo -e "  ${BOLD}${WHITE}$(t templates_preview_title)${NC}" >&2
    echo -e "  ${DIM}$(printf '─%.0s' {1..55})${NC}" >&2
    echo -e "  ${WHITE}$(t templates_name)${NC}  $name" >&2
    echo -e "  ${WHITE}$(t templates_source)${NC}  $source" >&2
    echo -e "  ${WHITE}$(t templates_description)${NC}  $description" >&2

    if [ -n "$preview_url" ]; then
        echo "" >&2
        echo -e "  ${GREEN}$(t templates_preview)${NC} ${CYAN}${preview_url}${NC}" >&2
        echo -e "  ${DIM}$(t templates_preview_hint)${NC}" >&2
    fi

    if [ -n "$repo_url" ]; then
        echo -e "  ${DIM}$(t templates_repo)    ${repo_url}${NC}" >&2
    fi

    # Thanks
    echo "" >&2
    echo -e "  ${MAGENTA}$(tf templates_thanks "$source")${NC}" >&2

    echo -e "  ${DIM}$(printf '─%.0s' {1..55})${NC}" >&2
    echo "" >&2

    if ! confirm "$(t templates_install_this)"; then
        return 1
    fi
    return 0
}

# ── Template download (from catalog) ───────────────────────────────────
download_template() {
    local tpl_id="$1"
    local output_dir="${2:-$TEMPLATES_CACHE}"
    local info
    info=$(get_template_info "$tpl_id")

    local repo_url sparse_path source name
    repo_url=$(echo "$info" | jq -r '.repo_url')
    sparse_path=$(echo "$info" | jq -r '.sparse_path')
    source=$(echo "$info" | jq -r '.source')
    name=$(echo "$info" | jq -r '.name')

    local clone_dir="$output_dir/${tpl_id}"
    [[ "$tpl_id" =~ ^[A-Za-z0-9._-]+$ ]] || {
        log_error "Некорректный идентификатор шаблона"
        return 1
    }
    mkdir -p -m 700 "$output_dir"
    chmod 700 "$output_dir" 2>/dev/null || true
    rm -rf -- "$clone_dir"
    mkdir -p -m 700 "$clone_dir"

    log_info "$(tf templates_downloading "$name")"

    # HTML5 UP — one repo with folders
    if [ "$source" = "html5up" ]; then
        local work_dir tmp_clone
        work_dir=$(mktemp -d /tmp/gotelegram-template.XXXXXX) || return 1
        tmp_clone="$work_dir/repo"

        # Sparse checkout
        git clone --depth 1 --filter=blob:none --sparse "$repo_url" "$tmp_clone" 2>/dev/null
        if [ $? -ne 0 ]; then
            # Fallback: full clone
            git clone --depth 1 "$repo_url" "$tmp_clone" 2>/dev/null
        fi

        if [ -d "$tmp_clone" ]; then
            cd "$tmp_clone" && git sparse-checkout set "$sparse_path" 2>/dev/null
            if [ -d "$tmp_clone/$sparse_path" ]; then
                cp -r "$tmp_clone/$sparse_path"/* "$clone_dir/"
            fi
            cd - >/dev/null
        fi
        rm -rf -- "$work_dir"

    # learning-zone — one big repo
    elif [ "$source" = "learning-zone" ]; then
        local work_dir tmp_clone
        work_dir=$(mktemp -d /tmp/gotelegram-template.XXXXXX) || return 1
        tmp_clone="$work_dir/repo"

        git clone --depth 1 --filter=blob:none --sparse "$repo_url" "$tmp_clone" 2>/dev/null
        if [ $? -ne 0 ]; then
            git clone --depth 1 "$repo_url" "$tmp_clone" 2>/dev/null
        fi

        if [ -d "$tmp_clone" ]; then
            cd "$tmp_clone" && git sparse-checkout set "$sparse_path" 2>/dev/null
            if [ -d "$tmp_clone/$sparse_path" ]; then
                cp -r "$tmp_clone/$sparse_path"/* "$clone_dir/"
            fi
            cd - >/dev/null
        fi
        rm -rf -- "$work_dir"

    # StartBootstrap — each template in its own repo
    elif [ "$source" = "startbootstrap" ]; then
        local work_dir sb_tmp
        work_dir=$(mktemp -d /tmp/gotelegram-template.XXXXXX) || return 1
        sb_tmp="$work_dir/repo"
        git clone --depth 1 "$repo_url" "$sb_tmp" 2>/dev/null
        if [ -d "$sb_tmp" ]; then
            rm -rf "$sb_tmp/.git"
            # StartBootstrap stores production files in dist/
            if [ -f "$sb_tmp/dist/index.html" ]; then
                cp -r "$sb_tmp/dist/"* "$clone_dir/"
            elif [ -f "$sb_tmp/index.html" ]; then
                cp -r "$sb_tmp/"* "$clone_dir/"
            else
                local found_index
                found_index=$(find "$sb_tmp" -name "index.html" -type f 2>/dev/null | head -1)
                if [ -n "$found_index" ]; then
                    local found_dir
                    found_dir=$(dirname "$found_index")
                    cp -r "$found_dir/"* "$clone_dir/"
                fi
            fi
        fi
        rm -rf -- "$work_dir"

    # ThemeWagon / ColorlibHQ — each template in its own repo
    elif [ "$source" = "themewagon" ] || [ "$source" = "colorlib" ]; then
        local work_dir tw_tmp
        work_dir=$(mktemp -d /tmp/gotelegram-template.XXXXXX) || return 1
        tw_tmp="$work_dir/repo"
        git clone --depth 1 "$repo_url" "$tw_tmp" 2>/dev/null
        if [ -d "$tw_tmp" ]; then
            rm -rf "$tw_tmp/.git"
            if [ -f "$tw_tmp/dist/index.html" ]; then
                cp -r "$tw_tmp/dist/"* "$clone_dir/"
            elif [ -f "$tw_tmp/index.html" ]; then
                cp -r "$tw_tmp/"* "$clone_dir/"
            else
                local found_index
                found_index=$(find "$tw_tmp" -name "index.html" -type f -maxdepth 3 2>/dev/null | head -1)
                if [ -n "$found_index" ]; then
                    local found_dir
                    found_dir=$(dirname "$found_index")
                    cp -r "$found_dir/"* "$clone_dir/"
                fi
            fi
        fi
        rm -rf -- "$work_dir"

    # dawidolko — one big repo with folders (similar to learning-zone)
    elif [ "$source" = "dawidolko" ]; then
        local work_dir tmp_clone
        work_dir=$(mktemp -d /tmp/gotelegram-template.XXXXXX) || return 1
        tmp_clone="$work_dir/repo"
        git clone --depth 1 --filter=blob:none --sparse "$repo_url" "$tmp_clone" 2>/dev/null
        if [ $? -ne 0 ]; then
            git clone --depth 1 "$repo_url" "$tmp_clone" 2>/dev/null
        fi
        if [ -d "$tmp_clone" ]; then
            cd "$tmp_clone" && git sparse-checkout set "$sparse_path" 2>/dev/null
            if [ -d "$tmp_clone/$sparse_path" ]; then
                cp -r "$tmp_clone/$sparse_path"/* "$clone_dir/"
            fi
            cd - >/dev/null
        fi
        rm -rf -- "$work_dir"
    fi

    # Check result
    if [ -f "$clone_dir/index.html" ]; then
        log_success "$(tf templates_downloaded "$name")"
        echo "$clone_dir"
        return 0
    else
        # fallback: find index.html in subfolders (non-standard structure)
        local fallback_index
        fallback_index=$(find "$clone_dir" -name "index.html" -type f 2>/dev/null | head -1)
        if [ -n "$fallback_index" ]; then
            local fallback_dir
            fallback_dir=$(dirname "$fallback_index")
            if [ "$fallback_dir" != "$clone_dir" ]; then
                cp -r "$fallback_dir/"* "$clone_dir/"
                log_success "$(tf templates_downloaded_subfolder "$name")"
                echo "$clone_dir"
                return 0
            fi
        fi
        log_error "$(t templates_no_index)"
        log_dim "$(tf templates_path "$clone_dir")"
        ls -la "$clone_dir" 2>/dev/null >&2
        return 1
    fi
}

# ── Custom git URL helpers ─────────────────────────────────────────────

# Validate a user-supplied git URL
# Accepts: https://host/path[.git][@branch]
# Rejects: ssh://, git://, file://, absolute file paths
_validate_custom_git_url() {
    local url="$1"
    # Must begin with https://
    [[ "$url" =~ ^https:// ]] || return 1
    # Reject shell metacharacters that could be exploited
    [[ "$url" =~ [[:space:]\;\`\$\(\)\<\>\|\\\&] ]] && return 1
    # Reasonable length limit
    [ "${#url}" -gt 512 ] && return 1
    return 0
}

# Parse URL → sets CUSTOM_GIT_CLEAN and CUSTOM_GIT_BRANCH globals
_parse_custom_git_url() {
    local url="$1"
    CUSTOM_GIT_CLEAN=""
    CUSTOM_GIT_BRANCH=""
    # Handle trailing @branch
    if [[ "$url" =~ ^(https://[^@]+)@([A-Za-z0-9._/-]+)$ ]]; then
        CUSTOM_GIT_CLEAN="${BASH_REMATCH[1]}"
        CUSTOM_GIT_BRANCH="${BASH_REMATCH[2]}"
    else
        CUSTOM_GIT_CLEAN="$url"
    fi
    # Strip trailing slash
    CUSTOM_GIT_CLEAN="${CUSTOM_GIT_CLEAN%/}"
    # Append .git if missing (works better with git clone on some hosts)
    if [[ ! "$CUSTOM_GIT_CLEAN" =~ \.git$ ]]; then
        CUSTOM_GIT_CLEAN="${CUSTOM_GIT_CLEAN}.git"
    fi
}

# Check repo size (in MB) by inspecting cloned directory
_clone_dir_size_mb() {
    local dir="$1"
    du -sm "$dir" 2>/dev/null | awk '{print $1}'
}

# ── Show detailed help for custom git template ─────────────────────────
show_custom_git_help() {
    local line
    line=$(printf '─%.0s' $(seq 1 60))
    echo "" >&2
    echo -e "  ${BOLD}${GREEN}$(t custom_git_title)${NC}" >&2
    echo -e "  ${DIM}${line}${NC}" >&2
    echo -e "  $(t custom_git_help_1)" >&2
    echo -e "  $(t custom_git_help_2)" >&2
    echo -e "  $(t custom_git_help_3)" >&2
    echo "" >&2
    echo -e "  ${BOLD}${WHITE}$(t custom_git_formats)${NC}" >&2
    echo -e "  ${CYAN}$(t custom_git_fmt_github)${NC}" >&2
    echo -e "  ${CYAN}$(t custom_git_fmt_gitlab)${NC}" >&2
    echo -e "  ${CYAN}$(t custom_git_fmt_gitext)${NC}" >&2
    echo -e "  ${CYAN}$(t custom_git_fmt_branch)${NC}" >&2
    echo "" >&2
    echo -e "  ${BOLD}${WHITE}$(t custom_git_auto_detect)${NC}" >&2
    echo -e "  $(t custom_git_auto_1)" >&2
    echo -e "  $(t custom_git_auto_2)" >&2
    echo -e "  $(t custom_git_auto_3)" >&2
    echo -e "  $(t custom_git_auto_4)" >&2
    echo "" >&2
    echo -e "  ${BOLD}${WHITE}$(t custom_git_requirements)${NC}" >&2
    echo -e "  ${YELLOW}$(t custom_git_req_1)${NC}" >&2
    echo -e "  ${YELLOW}$(t custom_git_req_2)${NC}" >&2
    echo -e "  ${YELLOW}$(t custom_git_req_3)${NC}" >&2
    echo -e "  ${YELLOW}$(t custom_git_req_4)${NC}" >&2
    echo "" >&2
    echo -e "  ${BOLD}${WHITE}$(t custom_git_examples)${NC}" >&2
    echo -e "  ${DIM}$(t custom_git_ex_1)${NC}" >&2
    echo -e "  ${DIM}$(t custom_git_ex_2)${NC}" >&2
    echo -e "  ${DIM}${line}${NC}" >&2
    echo "" >&2
}

# ── Download a custom git template ─────────────────────────────────────
# Prompts user for a URL (unless passed), clones, detects index.html,
# copies result into $output_dir/custom_<hash>, echoes the final path.
download_custom_git_template() {
    local url="${1:-}"
    local output_dir="${2:-$TEMPLATES_CACHE}"

    show_custom_git_help

    if [ -z "$url" ]; then
        echo -ne "  ${WHITE}$(t custom_git_enter_url)${NC} " >&2
        read -r url
        url=$(echo "$url" | tr -d '\r\n[:space:]')
    fi

    if [ -z "$url" ]; then
        log_error "$(t custom_git_empty)"
        return 1
    fi

    if ! _validate_custom_git_url "$url"; then
        log_error "$(t custom_git_bad_url)"
        return 1
    fi

    _parse_custom_git_url "$url"
    local clean_url="$CUSTOM_GIT_CLEAN"
    local branch="$CUSTOM_GIT_BRANCH"

    # Stable-ish directory name from a hash of the original URL
    local hash
    hash=$(echo -n "$url" | md5sum 2>/dev/null | awk '{print $1}' | head -c 10)
    [ -z "$hash" ] && hash=$(date +%s)
    local tpl_id="custom_${hash}"
    local clone_dir="$output_dir/${tpl_id}"
    local work_dir tmp_clone error_file
    work_dir=$(mktemp -d /tmp/gotelegram-template.XXXXXX) || return 1
    tmp_clone="$work_dir/repo"
    error_file="$work_dir/git-error.log"

    mkdir -p -m 700 "$output_dir"
    chmod 700 "$output_dir" 2>/dev/null || true
    rm -rf -- "$clone_dir"
    mkdir -p -m 700 "$clone_dir"

    log_info "$(t custom_git_cloning)"

    # Clone with timeout so a hung server can't freeze the installer
    local clone_status=0
    local git_args=("clone" "--depth" "1")
    [ -n "$branch" ] && git_args+=("--branch" "$branch")
    git_args+=("$clean_url" "$tmp_clone")

    if command -v timeout &>/dev/null; then
        timeout "$CUSTOM_GIT_CLONE_TIMEOUT" git "${git_args[@]}" 2>"$error_file"
        clone_status=$?
    else
        git "${git_args[@]}" 2>"$error_file"
        clone_status=$?
    fi

    if [ $clone_status -ne 0 ] || [ ! -d "$tmp_clone" ]; then
        local err_msg
        err_msg=$(head -3 "$error_file" 2>/dev/null | tr '\n' ' ')
        rm -rf -- "$work_dir" "$clone_dir"
        log_error "$(tf custom_git_clone_failed "${err_msg:-$clone_status}")"
        return 1
    fi

    # Drop .git before measuring size (we only care about payload)
    rm -rf "$tmp_clone/.git"

    # Size guard
    local size_mb
    size_mb=$(_clone_dir_size_mb "$tmp_clone")
    if [ -n "$size_mb" ] && [ "$size_mb" -gt "$CUSTOM_GIT_MAX_SIZE_MB" ]; then
        rm -rf -- "$work_dir" "$clone_dir"
        log_error "$(tf custom_git_too_big "${size_mb}MB")"
        return 1
    fi

    log_info "$(t custom_git_scanning)"

    # Priority list of common static-site output folders
    local candidates=("" "dist" "public" "build" "_site" "site" "docs" "out" "www")
    local found_dir=""
    for sub in "${candidates[@]}"; do
        local try_dir="$tmp_clone"
        [ -n "$sub" ] && try_dir="$tmp_clone/$sub"
        if [ -f "$try_dir/index.html" ]; then
            found_dir="$try_dir"
            break
        fi
    done

    # Fallback: search for any index.html in the repo (shallow depth first)
    if [ -z "$found_dir" ]; then
        local fallback_index
        fallback_index=$(find "$tmp_clone" -maxdepth 4 -name "index.html" -type f 2>/dev/null | head -1)
        if [ -n "$fallback_index" ]; then
            found_dir=$(dirname "$fallback_index")
        fi
    fi

    if [ -z "$found_dir" ] || [ ! -f "$found_dir/index.html" ]; then
        rm -rf -- "$work_dir" "$clone_dir"
        log_error "$(t custom_git_no_index)"
        return 1
    fi

    # Show what we found (human-friendly relative path)
    local rel_path="${found_dir#$tmp_clone}"
    rel_path="${rel_path#/}"
    [ -z "$rel_path" ] && rel_path="(root)"
    log_dim "$(tf custom_git_found_at "$rel_path")"

    # Copy the detected directory as the new template
    cp -r "$found_dir"/* "$clone_dir/" 2>/dev/null
    cp -r "$found_dir"/.[!.]* "$clone_dir/" 2>/dev/null

    rm -rf -- "$work_dir"

    if [ ! -f "$clone_dir/index.html" ]; then
        rm -rf "$clone_dir"
        log_error "$(t custom_git_no_index)"
        return 1
    fi

    # Remember the URL so users can see what template they used
    echo "$url" > "$clone_dir/.custom_git_source" 2>/dev/null

    log_success "$(tf custom_git_installed "$url")"
    echo "$clone_dir"
    return 0
}

# ── Full interactive template selection ───────────────────────────────
interactive_template_selection() {
    load_catalog || return 1

    # Category selection
    local cat_id
    cat_id=$(select_category)
    [ $? -ne 0 ] && return 1

    # Custom git URL path
    if [ "$cat_id" = "__custom_git__" ]; then
        local template_dir
        template_dir=$(download_custom_git_template)
        [ $? -ne 0 ] && return 1
        echo "$template_dir"
        return 0
    fi

    # Template selection
    local tpl_id
    tpl_id=$(select_template "$cat_id")
    [ $? -ne 0 ] && return 1

    # Download
    local template_dir
    template_dir=$(download_template "$tpl_id")
    [ $? -ne 0 ] && return 1

    echo "$template_dir"
    return 0
}


# pick_random_template_id — случайный id шаблона из каталога (для ленивого режима).
pick_random_template_id() {
    [ -f "$CATALOG_FILE" ] || return 1
    jq -r '.categories[].templates[].id' "$CATALOG_FILE" 2>/dev/null | shuf -n1
}

# ── Встроенные витрины IGProxy ──────────────────────────────────────────────
# Эти страницы разработаны вместе с IGProxy и входят в релиз. Интерактивный
# установщик использует только их; большой внешний каталог оставлен лишь для
# обратной совместимости со старым меню смены шаблона.
IGPROXY_SITE_PRESETS_DIR="${IGPROXY_SITE_PRESETS_DIR:-$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")/site-presets}"

igproxy_site_preset_rows() {
    cat <<'EOF'
random-gallery|Рандомный сайт|Одна из 10 самостоятельных витрин при каждом открытии|random-gallery|auto
story-editorial|Ночная редакция|Светлая газетная обложка с крупной типографикой|random-gallery|editorial
story-transit|Лунное депо|Контрастное транспортное табло и лунный вагон|random-gallery|transit
story-cartography|Картографы дождя|Бумажная карта, координаты и новая линия маршрута|random-gallery|cartography
story-terminal|Тихая мастерская|Инженерный терминал с зелёным свечением|random-gallery|terminal
story-botanical|Оранжерея мостов|Мягкий ботанический атлас и органические формы|random-gallery|botanical
story-postcard|Облачная почта|Воздушная открытка с конвертом и чистым небом|random-gallery|postcard
story-tearoom|Чайная у перевала|Тёплая вывеска старой чайной и второй перевал|random-gallery|tearoom
story-beacon|Бумажный маяк|Морская сигнальная панель и геометричный луч|random-gallery|beacon
story-poster|Оркестр обходных нот|Яркий музыкальный постер с ритмичными формами|random-gallery|poster
story-playground|Сад воздушных троп|Игровая иллюстрация с улиткой и мягкими карточками|random-gallery|playground
route-workshop|Маршрутная мастерская|Трёхмерная мастерская со светящимися маршрутами|route-workshop|auto
glass-garden|Сад за стеклом|Светлая басня о хранителях дверей|glass-garden|auto
open-library|Библиотека открытых окон|Ночная история о совах, ставнях и книгах-лодках|open-library|auto
EOF
}

igproxy_site_preset_definition() {
    local wanted="$1"
    igproxy_site_preset_rows | awk -F'|' -v wanted="$wanted" '$1 == wanted { print; found=1; exit } END { exit(found ? 0 : 1) }'
}

interactive_igproxy_site_preset_selection() {
    local rows=() row id name description source layout choice i=1
    while IFS= read -r row; do
        [ -n "$row" ] && rows+=("$row")
    done < <(igproxy_site_preset_rows)

    type ig_ui_clear >/dev/null 2>&1 && ig_ui_clear
    if type ig_ui_logo >/dev/null 2>&1; then
        ig_ui_logo "Витрина сайта"
        ig_ui_stepper 3 "Роль" "Проверка" "Публикация" "Установка"
        ig_ui_heading "ВСТРОЕННЫЕ САЙТЫ" "Выберите витрину IGProxy" \
            "Все варианты хранятся локально и не скачиваются со сторонних репозиториев."
    else
        echo "" >&2
        echo "  Встроенные сайты IGProxy:" >&2
    fi

    for row in "${rows[@]}"; do
        IFS='|' read -r id name description source layout <<< "$row"
        printf '  %s%2d%s  %s%-28s%s %s%s%s\n' \
            "${IG_UI_CYAN:-${CYAN:-}}" "$i" "${IG_UI_RESET:-${NC:-}}" \
            "${IG_UI_BOLD:-${BOLD:-}}" "$name" "${IG_UI_RESET:-${NC:-}}" \
            "${IG_UI_MUTED:-${DIM:-}}" "$description" "${IG_UI_RESET:-${NC:-}}" >&2
        i=$((i + 1))
    done

    while true; do
        printf '\n  %s%s%s Вариант [1]: ' \
            "${IG_UI_CYAN:-${CYAN:-}}" "$(type ig_ui_symbol >/dev/null 2>&1 && ig_ui_symbol "❯" ">" || printf '>')" \
            "${IG_UI_RESET:-${NC:-}}" >&2
        if [ -n "${IG_UI_TTY:-}" ]; then
            IFS= read -r choice < "$IG_UI_TTY" || choice=""
        else
            IFS= read -r choice || choice=""
        fi
        choice="${choice:-1}"
        case "$choice" in 0|q|Q) return 1 ;; esac
        if [[ "$choice" =~ ^[0-9]+$ ]] &&
           [ "$choice" -ge 1 ] && [ "$choice" -le "${#rows[@]}" ]; then
            IFS='|' read -r id name description source layout <<< "${rows[$((choice - 1))]}"
            printf '%s\n' "$id"
            return 0
        fi
        log_error "Введите номер от 1 до ${#rows[@]}."
    done
}

prepare_igproxy_site_preset() {
    local preset_id="$1" proxy_link="$2" definition source_id layout output_dir page
    command -v python3 >/dev/null 2>&1 || {
        log_error "Для подготовки встроенной витрины нужен python3."
        log_dim "Установите пакет python3 и повторите запуск IGProxy."
        return 1
    }
    [[ "$preset_id" =~ ^[a-z0-9-]+$ ]] || return 1
    definition=$(igproxy_site_preset_definition "$preset_id") || return 1
    IFS='|' read -r _ _ _ source_id layout <<< "$definition"
    [ -f "$IGPROXY_SITE_PRESETS_DIR/$source_id/index.html" ] || {
        log_error "Встроенная витрина не найдена: $preset_id"
        return 1
    }

    output_dir="$TEMPLATES_CACHE/igproxy-$preset_id"
    mkdir -p -m 700 "$TEMPLATES_CACHE"
    rm -rf -- "$output_dir"
    mkdir -p -m 700 "$output_dir"
    cp -a "$IGPROXY_SITE_PRESETS_DIR/$source_id/." "$output_dir/" || {
        log_error "Не удалось скопировать встроенную витрину $preset_id."
        return 1
    }

    while IFS= read -r -d '' page; do
        if ! python3 -c '
import pathlib
import sys

page = pathlib.Path(sys.argv[1])
layout = sys.argv[2]
proxy_link = open(3, encoding="utf-8").read().strip()
source = page.read_text(encoding="utf-8")
source = source.replace("__PROXY_LINK__", proxy_link).replace("__LAYOUT__", layout)
page.write_text(source, encoding="utf-8")
' "$page" "$layout" 3<<< "$proxy_link"; then
            log_error "Не удалось подготовить HTML встроенной витрины $preset_id."
            return 1
        fi
    done < <(find "$output_dir" -type f -name '*.html' -print0)
    printf '%s\n' "$output_dir"
}
