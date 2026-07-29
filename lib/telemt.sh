#!/bin/bash
# GoTelegram v2.5.0 — Управление telemt binary
# Скачивание, обновление, запуск, остановка через systemd

TELEMT_GITHUB="telemt/telemt"
TELEMT_RELEASE_API="https://api.github.com/repos/${TELEMT_GITHUB}/releases/latest"
TELEMT_USER="telemt"
TELEMT_GROUP="telemt"

# ── Получение последней версии ───────────────────────────────────────────────
get_latest_telemt_version() {
    local resp
    resp=$(curl -s --max-time 10 "$TELEMT_RELEASE_API" 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$resp" ]; then
        log_error "Не удалось получить информацию о релизах telemt"
        return 1
    fi
    echo "$resp" | jq -r '.tag_name // empty'
}

# Метаданные последних релизов ядра: строки "tag|YYYY-MM-DD|стабильная|предрелиз".
_telemt_releases_meta() {
    local resp
    resp=$(curl -s --max-time 10 "https://api.github.com/repos/${TELEMT_GITHUB}/releases?per_page=12" 2>/dev/null)
    [ -z "$resp" ] && return 1
    echo "$resp" | jq -r '.[] | "\(.tag_name)|\(.published_at[0:10])|\(if .prerelease then "предрелиз" else "стабильная" end)"' 2>/dev/null
}

get_telemt_download_url() {
    local version="${1:-}"
    local libc_flavor="${2:-gnu}"
    local api="$TELEMT_RELEASE_API"
    if [ -n "$version" ] && [ "$version" != "latest" ]; then
        api="https://api.github.com/repos/${TELEMT_GITHUB}/releases/tags/${version}"
    fi
    local arch
    arch=$(get_arch)
    local resp
    resp=$(curl -s --max-time 10 "$api" 2>/dev/null)
    if [ -z "$resp" ]; then return 1; fi

    # URL format: telemt-x86_64-linux-gnu.tar.gz (arch BEFORE linux)
    local arch_pattern
    case "$arch" in
        amd64)  arch_pattern="(amd64|x86_64)" ;;
        arm64)  arch_pattern="(arm64|aarch64)" ;;
        armv7)  arch_pattern="(armv7|arm)" ;;
        *)      arch_pattern="${arch}" ;;
    esac

    case "$libc_flavor" in
        gnu|musl) ;;
        *) return 1 ;;
    esac

    echo "$resp" | jq -r ".assets[].browser_download_url" 2>/dev/null \
        | grep -iE "$arch_pattern" \
        | grep -i "linux" \
        | grep -v "sha256" \
        | grep -vi -- "-v3-" \
        | grep -i -- "linux-${libc_flavor}" \
        | head -1
}

# ── Установленная версия ─────────────────────────────────────────────────────
get_installed_telemt_version() {
    if [ -x "$TELEMT_BIN" ]; then
        "$TELEMT_BIN" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
    else
        echo ""
    fi
}

is_telemt_installed() {
    [ -x "$TELEMT_BIN" ]
}

# Целевая версия ядра: из config.json telemt_version, иначе глобал TELEMT_VERSION_PREF,
# иначе последний стабильный релиз. Пин остаётся аварийным fallback.
telemt_target_version() {
    local v
    v=$(read_config_or_default telemt_version "" 2>/dev/null)
    [ -z "$v" ] && v="${TELEMT_VERSION_PREF:-}"
    case "$v" in
        ""|latest|recommended)
            get_latest_telemt_version 2>/dev/null || echo "${TELEMT_PINNED_VERSION:-3.4.25}"
            ;;
        pinned) echo "${TELEMT_PINNED_VERSION:-3.4.25}" ;;
        *)                     echo "$v" ;;
    esac
}

telemt_system_libc() {
    if ldd --version 2>&1 | grep -qi musl; then
        printf 'musl\n'
    else
        printf 'gnu\n'
    fi
}

# ── Скачивание и установка ───────────────────────────────────────────────────
download_telemt() {
    local version="${1:-$(telemt_target_version)}"
    local libc_flavor="${2:-$(telemt_system_libc)}"
    local allow_musl_fallback="${3:-1}"
    local url
    url=$(get_telemt_download_url "$version" "$libc_flavor")
    if [ -z "$url" ]; then
        log_error "Не найден ${libc_flavor}-бинарник telemt для архитектуры $(get_arch)"
        return 1
    fi

    local tmp_dir tmp_file checksum_file extract_dir staged_bin backup_tmp
    tmp_dir=$(mktemp -d /tmp/telemt-download.XXXXXX) || return 1
    chmod 700 "$tmp_dir"
    tmp_file="$tmp_dir/asset"
    checksum_file="$tmp_dir/asset.sha256"
    extract_dir="$tmp_dir/extract"
    log_info "Скачивание telemt ${version} (${libc_flavor}): $url"

    if ! curl -L -s --max-time 120 -o "$tmp_file" "$url"; then
        log_error "Ошибка скачивания telemt"
        rm -rf -- "$tmp_dir"
        return 1
    fi

    # Release-asset checksum is published next to every supported archive.
    # Fail closed: silently installing an unverified proxy binary is not safe.
    if ! curl -L -fsS --max-time 30 -o "$checksum_file" "${url}.sha256"; then
        log_error "Не удалось скачать контрольную сумму telemt"
        rm -rf -- "$tmp_dir"
        return 1
    fi
    local expected_sha actual_sha
    expected_sha=$(grep -oE '[a-fA-F0-9]{64}' "$checksum_file" | head -1 | tr 'A-F' 'a-f')
    actual_sha=$(sha256sum "$tmp_file" 2>/dev/null | awk '{print $1}')
    if [ -z "$expected_sha" ] || [ "$actual_sha" != "$expected_sha" ]; then
        log_error "Контрольная сумма telemt не совпала"
        rm -rf -- "$tmp_dir"
        return 1
    fi
    log_dim "SHA-256 telemt подтверждён"

    # Проверяем что файл не пустой и не HTML
    local file_size
    file_size=$(stat -c%s "$tmp_file" 2>/dev/null || echo 0)
    if [ "$file_size" -lt 1000 ]; then
        log_error "Скачанный файл слишком маленький ($file_size байт) — возможна ошибка сети"
        rm -rf -- "$tmp_dir"
        return 1
    fi

    # Определяем тип файла и распаковываем
    local mime extracted=""
    mime=$(file -b --mime-type "$tmp_file" 2>/dev/null)
    mkdir -p "$extract_dir"

    case "$mime" in
        application/gzip|application/x-gzip)
            tar xzf "$tmp_file" -C "$extract_dir" 2>/dev/null
            extracted=$(find "$extract_dir" -name "telemt" -type f 2>/dev/null | head -1)
            if [ -z "$extracted" ]; then
                # Может быть просто gzip без tar
                gunzip -c "$tmp_file" > "$extract_dir/telemt_bin" 2>/dev/null
                extracted="$extract_dir/telemt_bin"
            fi
            ;;
        application/x-tar)
            tar xf "$tmp_file" -C "$extract_dir" 2>/dev/null
            extracted=$(find "$extract_dir" -name "telemt" -type f 2>/dev/null | head -1)
            ;;
        application/zip)
            unzip -o "$tmp_file" -d "$extract_dir" 2>/dev/null
            extracted=$(find "$extract_dir" -name "telemt" -type f 2>/dev/null | head -1)
            ;;
        application/octet-stream|application/x-executable)
            extracted="$tmp_file"
            ;;
        *)
            # Пробуем определить по содержимому
            if file "$tmp_file" 2>/dev/null | grep -q "ELF"; then
                extracted="$tmp_file"
            else
                # Пробуем как tar.gz
                tar xzf "$tmp_file" -C "$extract_dir" 2>/dev/null
                extracted=$(find "$extract_dir" -name "telemt" -type f 2>/dev/null | head -1)
            fi
            ;;
    esac

    if [ -z "$extracted" ] || [ ! -f "$extracted" ]; then
        log_error "Не удалось извлечь бинарник telemt (mime: $mime)"
        rm -rf -- "$tmp_dir"
        return 1
    fi

    # Validate in staging, then atomically rename on the same filesystem.
    staged_bin=$(mktemp "${TELEMT_BIN}.new.XXXXXX") || {
        rm -rf -- "$tmp_dir"
        return 1
    }
    local probe_output="" probe_rc=0
    if ! install -m 755 "$extracted" "$staged_bin"; then
        log_error "Не удалось подготовить бинарник telemt к запуску"
        rm -f -- "$staged_bin"
        rm -rf -- "$tmp_dir"
        return 1
    fi
    if probe_output=$("$staged_bin" --version 2>&1); then
        probe_rc=0
    else
        probe_rc=$?
    fi
    if [ "$probe_rc" -ne 0 ] || ! printf '%s\n' "$probe_output" | grep -Fq "$version"; then
        probe_output=$(printf '%s' "${probe_output:-нет сообщения от загрузчика}" \
            | tr '\r\n\t' '   ' | sed -E 's/[[:space:]]+/ /g' | cut -c1-320)
        log_warning "Сборка telemt (${libc_flavor}) не запустилась: ${probe_output} (code: ${probe_rc})."
        rm -f -- "$staged_bin"
        rm -rf -- "$tmp_dir"
        if [ "$libc_flavor" = "gnu" ] && [ "$allow_musl_fallback" = "1" ]; then
            log_info "Пробую совместимую статическую musl-сборку telemt той же версии."
            download_telemt "$version" "musl" "0"
            return $?
        fi
        log_error "Скачанный бинарник telemt не прошёл проверку запуска/версии"
        return 1
    fi
    if [ -x "$TELEMT_BIN" ]; then
        backup_tmp=$(mktemp "${TELEMT_BIN}.rollback.XXXXXX") || {
            rm -f -- "$staged_bin"
            rm -rf -- "$tmp_dir"
            return 1
        }
        if ! cp -a "$TELEMT_BIN" "$backup_tmp" || \
           ! chmod 755 "$backup_tmp" || \
           ! mv -f -- "$backup_tmp" "${TELEMT_BIN}.rollback"; then
            rm -f -- "$backup_tmp" "$staged_bin"
            rm -rf -- "$tmp_dir"
            return 1
        fi
    fi
    if ! mv -f -- "$staged_bin" "$TELEMT_BIN"; then
        rm -f -- "$staged_bin"
        rm -rf -- "$tmp_dir"
        return 1
    fi
    rm -rf -- "$tmp_dir"
    log_success "telemt $(get_installed_telemt_version) установлен в $TELEMT_BIN"
    return 0
}

rollback_telemt_binary() {
    local restore_tmp
    [ -x "${TELEMT_BIN}.rollback" ] || return 1
    restore_tmp=$(mktemp "${TELEMT_BIN}.restore.XXXXXX") || return 1
    if ! cp -a "${TELEMT_BIN}.rollback" "$restore_tmp" || \
       ! chmod 755 "$restore_tmp" || \
       ! "$restore_tmp" --version >/dev/null 2>&1 || \
       ! mv -f -- "$restore_tmp" "$TELEMT_BIN"; then
        rm -f -- "$restore_tmp"
        return 1
    fi
}

commit_telemt_binary() {
    rm -f -- "${TELEMT_BIN}.rollback"
}

wait_telemt_ready() {
    local timeout="${1:-90}" port elapsed=0
    port=$(get_config_value port "$TELEMT_CONFIG" 2>/dev/null || echo 443)
    while [ "$elapsed" -lt "$timeout" ]; do
        systemctl is-active --quiet "$TELEMT_SERVICE" || return 1
        if ss -H -ltn "sport = :${port}" 2>/dev/null | grep -q .; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

# ── Системный пользователь ───────────────────────────────────────────────────
create_telemt_user() {
    if ! id "$TELEMT_USER" &>/dev/null; then
        useradd -r -s /usr/sbin/nologin -d /etc/telemt "$TELEMT_USER" 2>/dev/null
        log_dim "Создан системный пользователь: $TELEMT_USER"
    fi
}

# ── Systemd сервис ───────────────────────────────────────────────────────────
install_telemt_service() {
    local config_path="${1:-$TELEMT_CONFIG}"

    cat > "/etc/systemd/system/${TELEMT_SERVICE}.service" << EOF
[Unit]
Description=goTelegram Pro MTProxy (telemt engine)
Documentation=https://github.com/telemt/telemt
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=$TELEMT_BIN run $config_path
Restart=always
RestartSec=5
LimitNOFILE=65535

# Писহемая рабочая папка для снапшота beobachten.txt и кэша proxy-config
# (иначе при ProtectSystem=full telemt не может писать в /etc -> WARN каждые 15с)
WorkingDirectory=/var/lib/telemt
StateDirectory=telemt

# Безопасность
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

    mkdir -p /var/lib/telemt 2>/dev/null || true
    systemctl daemon-reload
    log_success "Systemd сервис $TELEMT_SERVICE создан"
}

# ── Управление сервисом ──────────────────────────────────────────────────────
# start_telemt ensures telemt is running with the CURRENT on-disk config.
# If the service is already active we must restart (not plain start) — otherwise
# the running process keeps its old in-memory config and the freshly generated
# /etc/telemt/config.toml is silently ignored. This was the root cause of the
# "lite-mode key doesn't work after reinstall" bug: telemt had loaded the
# previous Pro config (tls_domain=example.com) and was rejecting SNI=google.com
# clients with unknown_sni_action=Drop even though the on-disk config said
# tls_domain=google.com.
wait_telemt_ready() {
    local timeout="${1:-90}"
    local port elapsed=0
    port=$(awk '
        /^\[server\]/ { in_server=1; next }
        /^\[/ && in_server { exit }
        in_server && $1 == "port" {
            sub(/^[^=]*=[[:space:]]*/, "")
            gsub(/[[:space:]]/, "")
            print
            exit
        }
    ' "$TELEMT_CONFIG" 2>/dev/null)
    [[ "$port" =~ ^[0-9]+$ ]] || port=443

    while [ "$elapsed" -lt "$timeout" ]; do
        if ! systemctl is-active --quiet "$TELEMT_SERVICE" 2>/dev/null; then
            return 1
        fi
        if ss -ltnp 2>/dev/null | grep -E ":${port}\b" | grep -q "telemt"; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    return 1
}

start_telemt() {
    if systemctl is-active --quiet "$TELEMT_SERVICE" 2>/dev/null; then
        systemctl restart "$TELEMT_SERVICE" 2>/dev/null
    else
        systemctl start "$TELEMT_SERVICE" 2>/dev/null
    fi
    if wait_telemt_ready 90; then
        log_success "telemt запущен"
        return 0
    else
        log_error "telemt не запустился или не открыл порт"
        journalctl -u "$TELEMT_SERVICE" --no-pager -n 10 2>/dev/null
        return 1
    fi
}

stop_telemt() {
    if systemctl is-active --quiet "$TELEMT_SERVICE" 2>/dev/null; then
        systemctl stop "$TELEMT_SERVICE"
        log_success "telemt остановлен"
    else
        log_dim "telemt уже остановлен"
    fi
}

restart_telemt() {
    systemctl restart "$TELEMT_SERVICE" 2>/dev/null
    if wait_telemt_ready 90; then
        log_success "telemt перезапущен"
        return 0
    else
        log_error "telemt не перезапустился или не открыл порт"
        journalctl -u "$TELEMT_SERVICE" --no-pager -n 10 2>/dev/null
        return 1
    fi
}

enable_telemt() {
    systemctl enable "$TELEMT_SERVICE" 2>/dev/null
}

telemt_status() {
    if ! is_telemt_installed; then
        echo "not_installed"
        return
    fi
    if systemctl is-active --quiet "$TELEMT_SERVICE" 2>/dev/null; then
        echo "running"
    elif systemctl is-enabled --quiet "$TELEMT_SERVICE" 2>/dev/null; then
        echo "stopped"
    else
        echo "disabled"
    fi
}

telemt_logs() {
    local lines="${1:-40}"
    journalctl -u "$TELEMT_SERVICE" --no-pager -n "$lines" 2>/dev/null
}

telemt_uptime() {
    local started
    started=$(systemctl show "$TELEMT_SERVICE" --property=ActiveEnterTimestamp --value 2>/dev/null)
    if [ -n "$started" ] && [ "$started" != "" ]; then
        echo "$started"
    else
        echo "N/A"
    fi
}

# ── Обновление ───────────────────────────────────────────────────────────────
check_telemt_update() {
    local current latest
    current=$(get_installed_telemt_version)
    latest=$(get_latest_telemt_version)

    if [ -z "$current" ] || [ -z "$latest" ]; then
        return 1
    fi

    if [ "$current" != "$latest" ]; then
        echo "$latest"
        return 0  # есть обновление
    fi
    return 1  # актуально
}

update_telemt() {
    local latest
    latest=$(check_telemt_update)
    if [ $? -ne 0 ]; then
        log_info "telemt уже последней версии ($(get_installed_telemt_version))"
        return 0
    fi

    log_info "Доступно обновление: $(get_installed_telemt_version) → $latest"
    if ! confirm "Обновить telemt?"; then
        return 0
    fi

    stop_telemt
    if download_telemt; then
        if start_telemt && wait_telemt_ready 90; then
            commit_telemt_binary
            log_success "telemt обновлён до $latest"
        else
            stop_telemt || true
            if rollback_telemt_binary && start_telemt && wait_telemt_ready 90; then
                log_error "Новое ядро не запустилось; восстановлена предыдущая версия"
            else
                log_error "Новое ядро не запустилось, автоматическое восстановление тоже не прошло readiness"
            fi
            return 1
        fi
    else
        start_telemt
        log_error "Обновление не удалось"
        return 1
    fi
}

# ── Полная установка telemt ──────────────────────────────────────────────────
install_telemt_full() {
    log_step "Установка telemt"

    # Создаём директории
    mkdir -p /etc/telemt

    # Скачиваем бинарник
    run_with_spinner "Скачивание telemt" download_telemt || return 1

    # Устанавливаем systemd сервис
    install_telemt_service

    # Включаем автозапуск
    enable_telemt

    log_success "telemt готов к работе"
    return 0
}

# ── Удаление telemt ──────────────────────────────────────────────────────────
remove_telemt() {
    stop_telemt
    systemctl disable "$TELEMT_SERVICE" 2>/dev/null
    rm -f "/etc/systemd/system/${TELEMT_SERVICE}.service"
    systemctl daemon-reload
    rm -f "$TELEMT_BIN"
    rm -rf /etc/telemt
    log_success "telemt полностью удалён"
}
