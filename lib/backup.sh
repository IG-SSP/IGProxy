#!/bin/bash
# goTelegram Pro v2.5.0 — backup and restore (i18n-aware)

BACKUP_PASSPHRASE_FILE="${BACKUP_PASSPHRASE_FILE:-/etc/gotelegram/backup.passphrase}"

ensure_backup_passphrase_file() {
    if [ ! -f "$BACKUP_PASSPHRASE_FILE" ]; then
        mkdir -p -m 700 "$(dirname "$BACKUP_PASSPHRASE_FILE")"
        umask 077
        {
            printf 'gotelegram-'
            openssl rand -base64 36 | tr -d '\n'
            printf '\n'
        } > "$BACKUP_PASSPHRASE_FILE" || return 1
    fi
    chmod 600 "$BACKUP_PASSPHRASE_FILE" 2>/dev/null || return 1
}

backup_secure_cleanup() {
    local path="${1:-}"
    case "$path" in
        /tmp/gotelegram-backup.*|/tmp/gotelegram-restore.*)
            [ -n "$path" ] && rm -rf -- "$path"
            ;;
    esac
}

backup_archive_paths_are_safe() {
    local archive="$1"
    tar tzf "$archive" 2>/dev/null | awk '
        BEGIN { ok=1 }
        /^\// { ok=0 }
        /(^|\/)\.\.(\/|$)/ { ok=0 }
        /\\/ { ok=0 }
        END { exit(ok ? 0 : 1) }
    '
}

backup_verify_checksum() {
    local backup_file="$1"
    local checksum_file="${backup_file}.sha256"
    if [ ! -f "$checksum_file" ]; then
        log_error "Рядом с архивом нет файла контроля целостности: $(basename "$checksum_file")"
        return 1
    fi
    (
        cd "$(dirname "$backup_file")" &&
        sha256sum -c "$(basename "$checksum_file")" >/dev/null 2>&1
    )
}

create_backup_from_password_file() {
    local password_file="${1:-$BACKUP_PASSPHRASE_FILE}"
    [ -f "$password_file" ] || {
        log_error "Не найден ключ плановых бэкапов: $password_file"
        return 1
    }
    [ "$(stat -c '%a' "$password_file" 2>/dev/null)" = "600" ] || {
        log_error "Ключ бэкапов должен иметь права 600: $password_file"
        return 1
    }
    local password
    IFS= read -r password < "$password_file"
    [ ${#password} -ge 16 ] || {
        log_error "Ключ плановых бэкапов слишком короткий"
        return 1
    }
    create_backup "$password"
    password=""
}

restore_backup_from_password_file() {
    local backup_file="$1"
    local password_file="${2:-$BACKUP_PASSPHRASE_FILE}"
    local assume_yes="${3:-}"
    [ -f "$password_file" ] || {
        log_error "Не найден ключ бэкапа: $password_file"
        return 1
    }
    [ "$(stat -c '%a' "$password_file" 2>/dev/null)" = "600" ] || {
        log_error "Ключ бэкапа должен иметь права 600: $password_file"
        return 1
    }
    local password
    IFS= read -r password < "$password_file"
    restore_backup "$backup_file" "$password" "$assume_yes"
    local result=$?
    password=""
    return "$result"
}

# ── Создание бекапа ──────────────────────────────────────────────────────────
create_backup() {
    local password="$1"
    local output_dir="${2:-$BACKUP_DIR}"
    umask 077
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name work_dir tmp_dir suffix=0

    mkdir -p -m 700 "$output_dir"
    chmod 700 "$output_dir" 2>/dev/null || true
    work_dir=$(mktemp -d /tmp/gotelegram-backup.XXXXXX) || return 1
    while true; do
        if [ "$suffix" -eq 0 ]; then
            backup_name="gotelegram_backup_${timestamp}"
        else
            backup_name="gotelegram_backup_${timestamp}_${suffix}"
        fi
        tmp_dir="${work_dir}/${backup_name}"
        if [ ! -e "${output_dir}/${backup_name}.tar.gz" ] && \
           [ ! -e "${output_dir}/${backup_name}.tar.gz.gpg" ] && \
           [ ! -e "${output_dir}/${backup_name}.tar.gz.enc" ]; then
            break
        fi
        suffix=$((suffix + 1))
    done
    mkdir -p -m 700 "$tmp_dir"

    # Собираем файлы
    log_info "$(_t_or backup_collecting 'Собираю конфигурацию...')"

    # telemt конфиг
    if [ -f "$TELEMT_CONFIG" ]; then
        cp "$TELEMT_CONFIG" "$tmp_dir/config.toml"
    fi

    # goTelegram Pro конфиг
    if [ -f "$GOTELEGRAM_CONFIG" ]; then
        cp "$GOTELEGRAM_CONFIG" "$tmp_dir/gotelegram.json"
    fi
    if [ -f "$GOTELEGRAM_DIR/disabled_users.json" ]; then
        cp "$GOTELEGRAM_DIR/disabled_users.json" "$tmp_dir/disabled_users.json" 2>/dev/null
    fi
    if [ -f "$GOTELEGRAM_DIR/backup_schedule.json" ]; then
        cp "$GOTELEGRAM_DIR/backup_schedule.json" "$tmp_dir/backup_schedule.json" 2>/dev/null
    fi

    # Language marker (i18n)
    if [ -f "$GOTELEGRAM_DIR/.language" ]; then
        cp "$GOTELEGRAM_DIR/.language" "$tmp_dir/.language"
    fi

    # nginx конфиг (stealth mode)
    if [ -f "$NGINX_SITE_CONF" ]; then
        cp "$NGINX_SITE_CONF" "$tmp_dir/nginx.conf"
    fi

    # SSL сертификаты и renewal metadata для переносов между VPS
    local domain
    domain=$(config_get domain 2>/dev/null)
    if [ -n "$domain" ] && [ -d "/etc/letsencrypt/live/$domain" ]; then
        mkdir -p "$tmp_dir/letsencrypt/live" "$tmp_dir/letsencrypt/archive" "$tmp_dir/letsencrypt/renewal"
        cp -a "/etc/letsencrypt/live/$domain" "$tmp_dir/letsencrypt/live/" 2>/dev/null
        [ -d "/etc/letsencrypt/archive/$domain" ] && \
            cp -a "/etc/letsencrypt/archive/$domain" "$tmp_dir/letsencrypt/archive/" 2>/dev/null
        [ -f "/etc/letsencrypt/renewal/$domain.conf" ] && \
            cp -a "/etc/letsencrypt/renewal/$domain.conf" "$tmp_dir/letsencrypt/renewal/" 2>/dev/null
        log_dim "SSL сертификаты включены"
    fi

    # Шаблон сайта (если есть)
    if [ -d "$WEBSITE_ROOT" ] && [ -f "$WEBSITE_ROOT/index.html" ]; then
        mkdir -p "$tmp_dir/site"
        cp -a "$WEBSITE_ROOT/." "$tmp_dir/site/"
        log_dim "$(_t_or backup_site_included 'Шаблон сайта включён')"
    fi

    # Custom templates and catalog
    if [ -d "$GOTELEGRAM_DIR/custom_templates" ]; then
        mkdir -p "$tmp_dir/custom_templates"
        cp -a "$GOTELEGRAM_DIR/custom_templates/." "$tmp_dir/custom_templates/" 2>/dev/null
    fi
    if [ -f "$GOTELEGRAM_DIR/templates_catalog.json" ]; then
        cp "$GOTELEGRAM_DIR/templates_catalog.json" "$tmp_dir/templates_catalog.json" 2>/dev/null
    fi

    # Bot state (.env has BotFather token, so encrypted backups are strongly recommended)
    if [ -d "$BOT_DIR" ]; then
        mkdir -p "$tmp_dir/bot"
        [ -f "$BOT_DIR/.env" ] && cp "$BOT_DIR/.env" "$tmp_dir/bot/.env" 2>/dev/null
        [ -f "$BOT_DIR/i18n.py" ] && cp "$BOT_DIR/i18n.py" "$tmp_dir/bot/i18n.py" 2>/dev/null
        [ -d "$BOT_DIR/lang" ] && cp -a "$BOT_DIR/lang" "$tmp_dir/bot/" 2>/dev/null
    fi

    # Local web admin state
    if [ -d "$ADMIN_WEB_DIR" ]; then
        mkdir -p "$tmp_dir/admin_web"
        [ -f "$ADMIN_WEB_DIR/server.py" ] && cp "$ADMIN_WEB_DIR/server.py" "$tmp_dir/admin_web/server.py" 2>/dev/null
        [ -d "$ADMIN_WEB_DIR/static" ] && cp -a "$ADMIN_WEB_DIR/static" "$tmp_dir/admin_web/" 2>/dev/null
    fi

    # Traffic history
    if [ -f "$GOTELEGRAM_DIR/stats_history.csv" ]; then
        cp "$GOTELEGRAM_DIR/stats_history.csv" "$tmp_dir/stats_history.csv" 2>/dev/null
    fi
    if [ -f "$GOTELEGRAM_DIR/user_stats_history.csv" ]; then
        cp "$GOTELEGRAM_DIR/user_stats_history.csv" "$tmp_dir/user_stats_history.csv" 2>/dev/null
    fi
    if [ -f "$GOTELEGRAM_DIR/shared-443.json" ]; then
        cp "$GOTELEGRAM_DIR/shared-443.json" "$tmp_dir/shared-443.json" 2>/dev/null
    fi

    # Метаданные
    local ip mode engine lang port domain
    ip=$(get_server_ip)
    mode=$(config_get mode 2>/dev/null || echo "unknown")
    engine=$(config_get engine 2>/dev/null || echo "telemt")
    lang=$(type get_language &>/dev/null && get_language 2>/dev/null || echo "en")
    port=$(config_get port 2>/dev/null || echo "443")
    # Ensure port is numeric; fall back to 443 if garbage
    [[ "$port" =~ ^[0-9]+$ ]] || port=443
    domain=$(config_get domain 2>/dev/null || echo "")

    cat > "$tmp_dir/metadata.json" << EOMETA
{
    "backup_version": "1.6",
    "gotelegram_version": "$GOTELEGRAM_VERSION",
    "created_at": "$(date -Iseconds)",
    "hostname": "$(hostname)",
    "ip": "$ip",
    "engine": "$engine",
    "mode": "$mode",
    "language": "$lang",
    "port": $port,
    "domain": "$domain"
}
EOMETA

    # Архивируем
    local tar_file="${work_dir}/${backup_name}.tar.gz"
    if ! tar czf "$tar_file" -C "$work_dir" "$backup_name" 2>/dev/null; then
        log_error "$(_t_or backup_archive_err 'Ошибка создания архива')"
        backup_secure_cleanup "$work_dir"
        return 1
    fi

    if [ ! -f "$tar_file" ]; then
        log_error "$(_t_or backup_archive_missing 'Архив не создан')"
        backup_secure_cleanup "$work_dir"
        return 1
    fi

    # Шифруем если задан пароль
    local final_file=""
    if [ -n "$password" ]; then
        if ! command -v gpg >/dev/null 2>&1; then
            log_error "Для защищённого бэкапа нужен пакет gnupg"
            backup_secure_cleanup "$work_dir"
            return 1
        fi
        final_file="${output_dir}/${backup_name}.tar.gz.gpg"
        if ! printf '%s' "$password" | gpg --batch --yes --quiet \
            --pinentry-mode loopback --passphrase-fd 0 --symmetric \
            --cipher-algo AES256 --output "$final_file" "$tar_file" 2>/dev/null; then
            log_error "$(_t_or backup_encrypt_err 'Ошибка шифрования')"
            rm -f -- "$final_file"
            backup_secure_cleanup "$work_dir"
            return 1
        fi
        log_success "Бэкап зашифрован GPG/AES-256"
    else
        final_file="${output_dir}/${backup_name}.tar.gz"
        mv -- "$tar_file" "$final_file"
    fi

    chmod 600 "$final_file"
    (
        cd "$output_dir" &&
        sha256sum "$(basename "$final_file")" > "$(basename "$final_file").sha256"
    ) || {
        log_error "Не удалось создать файл контроля целостности"
        rm -f -- "$final_file" "${final_file}.sha256"
        backup_secure_cleanup "$work_dir"
        return 1
    }
    chmod 600 "${final_file}.sha256"

    # Очистка
    backup_secure_cleanup "$work_dir"

    local size
    size=$(du -h "$final_file" | cut -f1)
    if type tf &>/dev/null; then
        log_success "$(tf backup_created_fmt "$final_file" "$size")"
    else
        log_success "Бекап создан: $final_file ($size)"
    fi
    echo "$final_file"
    return 0
}

# ── Восстановление из бекапа ────────────────────────────────────────────────
restore_backup() {
    local backup_file="$1"
    local password="$2"
    local assume_yes="$3"

    if [ ! -f "$backup_file" ]; then
        if type tf &>/dev/null; then
            log_error "$(tf backup_file_not_found_fmt "$backup_file")"
        else
            log_error "Файл не найден: $backup_file"
        fi
        return 1
    fi

    umask 077
    if ! backup_verify_checksum "$backup_file"; then
        log_error "Контрольная сумма не совпала. Восстановление остановлено."
        return 1
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d /tmp/gotelegram-restore.XXXXXX) || return 1

    # Расшифровываем если нужно
    local tar_file=""
    if [[ "$backup_file" == *.gpg ]]; then
        if [ -z "$password" ]; then
            echo -ne "  $(_t_or backup_enter_pass 'Введите пароль от бекапа'): "
            read -rs password
            echo ""
        fi
        tar_file="${tmp_dir}/restore.tar.gz"
        if ! printf '%s' "$password" | gpg --batch --yes --quiet \
            --pinentry-mode loopback --passphrase-fd 0 --decrypt \
            --output "$tar_file" "$backup_file" 2>/dev/null; then
            log_error "$(_t_or backup_bad_pass 'Неверный пароль или повреждённый файл')"
            backup_secure_cleanup "$tmp_dir"
            return 1
        fi
        password=""
    elif [[ "$backup_file" == *.enc ]]; then
        if [ -z "$password" ]; then
            echo -ne "  $(_t_or backup_enter_pass 'Введите пароль от бекапа'): "
            read -rs password
            echo ""
        fi
        tar_file="${tmp_dir}/restore.tar.gz"
        if ! printf '%s' "$password" | openssl enc -aes-256-cbc -d -pbkdf2 \
            -in "$backup_file" -out "$tar_file" -pass stdin 2>/dev/null; then
            log_error "$(_t_or backup_bad_pass 'Неверный пароль или повреждённый файл')"
            backup_secure_cleanup "$tmp_dir"
            return 1
        fi
        password=""
    else
        tar_file="$backup_file"
    fi

    if ! backup_archive_paths_are_safe "$tar_file"; then
        log_error "Архив содержит небезопасные пути. Восстановление остановлено."
        backup_secure_cleanup "$tmp_dir"
        return 1
    fi

    # Распаковываем
    if ! tar xzf "$tar_file" -C "$tmp_dir" --no-same-owner --no-same-permissions 2>/dev/null; then
        log_error "$(_t_or backup_extract_err 'Ошибка распаковки архива')"
        backup_secure_cleanup "$tmp_dir"
        return 1
    fi

    # Находим папку бекапа
    local backup_dir
    backup_dir=$(find "$tmp_dir" -maxdepth 1 -type d -name "gotelegram_backup_*" | head -1)
    [ -z "$backup_dir" ] && backup_dir="$tmp_dir"

    # Legacy bot backups before v2.5.0 stored absolute paths directly in tar:
    # opt/gotelegram/config.json and etc/telemt/config.toml.
    if [ ! -f "$backup_dir/config.toml" ] && [ -f "$tmp_dir/etc/telemt/config.toml" ]; then
        cp "$tmp_dir/etc/telemt/config.toml" "$backup_dir/config.toml" 2>/dev/null || true
    fi
    if [ ! -f "$backup_dir/gotelegram.json" ] && [ -f "$tmp_dir/opt/gotelegram/config.json" ]; then
        cp "$tmp_dir/opt/gotelegram/config.json" "$backup_dir/gotelegram.json" 2>/dev/null || true
    fi
    if [ ! -f "$backup_dir/disabled_users.json" ] && [ -f "$tmp_dir/opt/gotelegram/disabled_users.json" ]; then
        cp "$tmp_dir/opt/gotelegram/disabled_users.json" "$backup_dir/disabled_users.json" 2>/dev/null || true
    fi

    # Проверяем метаданные
    if [ -f "$backup_dir/metadata.json" ]; then
        local bk_version bk_mode bk_ip bk_lang bk_date
        bk_version=$(jq -r '.gotelegram_version // "unknown"' "$backup_dir/metadata.json")
        bk_mode=$(jq -r '.mode // "unknown"' "$backup_dir/metadata.json")
        bk_ip=$(jq -r '.ip // "unknown"' "$backup_dir/metadata.json")
        bk_lang=$(jq -r '.language // "-"' "$backup_dir/metadata.json")
        bk_date=$(jq -r '.created_at // "-"' "$backup_dir/metadata.json")
        echo ""
        echo -e "  ${BOLD}${WHITE}📦 $(_t_or backup_label 'Бекап'):${NC}"
        echo -e "  $(_t_or backup_version_label 'Версия'): $bk_version | $(_t_or backup_mode_label 'Режим'): $bk_mode | IP: $bk_ip | $(_t_or backup_lang_label 'Язык'): $bk_lang"
        echo -e "  $(_t_or backup_date_label 'Дата'): $bk_date"
        echo ""
    fi

    if [ "$assume_yes" != "yes" ] && ! confirm "$(_t_or backup_confirm_restore 'Восстановить конфигурацию? Текущие настройки будут перезаписаны.')"; then
        backup_secure_cleanup "$tmp_dir"
        return 0
    fi

    # Останавливаем сервисы
    stop_telemt 2>/dev/null
    systemctl stop nginx 2>/dev/null

    # Восстанавливаем telemt конфиг
    if [ -f "$backup_dir/config.toml" ]; then
        mkdir -p /etc/telemt
        cp "$backup_dir/config.toml" "$TELEMT_CONFIG"
        chmod 600 "$TELEMT_CONFIG"
        log_success "$(_t_or backup_restored_telemt 'telemt конфиг восстановлен')"
    fi

    # Восстанавливаем goTelegram Pro конфиг
    if [ -f "$backup_dir/gotelegram.json" ]; then
        mkdir -p "$GOTELEGRAM_DIR"
        cp "$backup_dir/gotelegram.json" "$GOTELEGRAM_CONFIG"
        log_success "$(_t_or backup_restored_gotelegram 'GoTelegram конфиг восстановлен')"
    fi
    if [ -f "$backup_dir/disabled_users.json" ]; then
        mkdir -p "$GOTELEGRAM_DIR"
        cp "$backup_dir/disabled_users.json" "$GOTELEGRAM_DIR/disabled_users.json"
        chmod 600 "$GOTELEGRAM_DIR/disabled_users.json" 2>/dev/null || true
    fi
    if [ -f "$backup_dir/backup_schedule.json" ]; then
        mkdir -p "$GOTELEGRAM_DIR"
        cp "$backup_dir/backup_schedule.json" "$GOTELEGRAM_DIR/backup_schedule.json" 2>/dev/null
        chmod 600 "$GOTELEGRAM_DIR/backup_schedule.json" 2>/dev/null || true
        if command -v jq >/dev/null 2>&1; then
            local restored_schedule
            restored_schedule=$(jq -r '.frequency // "off"' "$GOTELEGRAM_DIR/backup_schedule.json" 2>/dev/null || echo "off")
            case "$restored_schedule" in
                off|daily|weekly|monthly) set_backup_schedule "$restored_schedule" >/dev/null 2>&1 || true ;;
            esac
        fi
    fi

    # Восстанавливаем language marker (i18n)
    if [ -f "$backup_dir/.language" ]; then
        mkdir -p "$GOTELEGRAM_DIR"
        cp "$backup_dir/.language" "$GOTELEGRAM_DIR/.language"
        log_success "$(_t_or backup_restored_lang 'Язык интерфейса восстановлен')"
    fi

    # Восстанавливаем nginx конфиг
    if [ -f "$backup_dir/nginx.conf" ]; then
        mkdir -p "$(dirname "$NGINX_SITE_CONF")" "$(dirname "$NGINX_SITE_LINK")"
        cp "$backup_dir/nginx.conf" "$NGINX_SITE_CONF"
        if [ "$NGINX_SITE_CONF" != "$NGINX_SITE_LINK" ]; then
            ln -sfn "$NGINX_SITE_CONF" "$NGINX_SITE_LINK"
        fi
        log_success "$(_t_or backup_restored_nginx 'nginx конфиг восстановлен')"
    fi

    # Восстанавливаем SSL / Let's Encrypt structure
    if [ -d "$backup_dir/letsencrypt" ]; then
        mkdir -p /etc/letsencrypt/live /etc/letsencrypt/archive /etc/letsencrypt/renewal
        [ -d "$backup_dir/letsencrypt/live" ] && cp -a "$backup_dir/letsencrypt/live/." /etc/letsencrypt/live/ 2>/dev/null
        [ -d "$backup_dir/letsencrypt/archive" ] && cp -a "$backup_dir/letsencrypt/archive/." /etc/letsencrypt/archive/ 2>/dev/null
        [ -d "$backup_dir/letsencrypt/renewal" ] && cp -a "$backup_dir/letsencrypt/renewal/." /etc/letsencrypt/renewal/ 2>/dev/null
        log_success "$(_t_or backup_restored_ssl 'SSL сертификаты восстановлены')"
    elif [ -d "$backup_dir/certs" ]; then
        local domain
        domain=$(config_get domain 2>/dev/null)
        if [ -n "$domain" ]; then
            local cert_dir="/etc/letsencrypt/live/$domain"
            mkdir -p "$cert_dir"
            cp "$backup_dir/certs/"* "$cert_dir/" 2>/dev/null
            log_success "$(_t_or backup_restored_ssl 'SSL сертификаты восстановлены')"
        fi
    fi

    # Восстанавливаем шаблон сайта
    if [ -d "$backup_dir/site" ]; then
        mkdir -p "$WEBSITE_ROOT"
        cp -a "$backup_dir/site/." "$WEBSITE_ROOT/"
        chown -R www-data:www-data "$WEBSITE_ROOT" 2>/dev/null || \
            chown -R nginx:nginx "$WEBSITE_ROOT" 2>/dev/null || true
        log_success "$(_t_or backup_restored_site 'Шаблон сайта восстановлен')"
    fi

    # Восстанавливаем custom templates/catalog/statistics
    if [ -d "$backup_dir/custom_templates" ]; then
        mkdir -p "$GOTELEGRAM_DIR/custom_templates"
        cp -a "$backup_dir/custom_templates/." "$GOTELEGRAM_DIR/custom_templates/" 2>/dev/null
        log_success "Пользовательские шаблоны восстановлены"
    fi
    if [ -f "$backup_dir/templates_catalog.json" ]; then
        cp "$backup_dir/templates_catalog.json" "$GOTELEGRAM_DIR/templates_catalog.json" 2>/dev/null
    fi
    if [ -f "$backup_dir/stats_history.csv" ]; then
        cp "$backup_dir/stats_history.csv" "$GOTELEGRAM_DIR/stats_history.csv" 2>/dev/null
        log_success "История статистики восстановлена"
    fi
    if [ -f "$backup_dir/user_stats_history.csv" ]; then
        cp "$backup_dir/user_stats_history.csv" "$GOTELEGRAM_DIR/user_stats_history.csv" 2>/dev/null
        log_success "История статистики пользователей восстановлена"
    fi
    if [ -f "$backup_dir/shared-443.json" ]; then
        cp "$backup_dir/shared-443.json" "$GOTELEGRAM_DIR/shared-443.json" 2>/dev/null
    fi

    # Восстанавливаем состояние бота
    if [ -d "$backup_dir/bot" ]; then
        mkdir -p "$BOT_DIR"
        [ -f "$backup_dir/bot/.env" ] && cp "$backup_dir/bot/.env" "$BOT_DIR/.env" 2>/dev/null && chmod 600 "$BOT_DIR/.env"
        [ -d "$backup_dir/bot/lang" ] && cp -a "$backup_dir/bot/lang" "$BOT_DIR/" 2>/dev/null
        [ -f "$backup_dir/bot/i18n.py" ] && cp "$backup_dir/bot/i18n.py" "$BOT_DIR/i18n.py" 2>/dev/null
        log_success "Конфигурация Telegram-бота восстановлена"
    fi

    # Восстанавливаем состояние локальной web-админки
    if [ -d "$backup_dir/admin_web" ]; then
        mkdir -p "$ADMIN_WEB_DIR"
        [ -f "$backup_dir/admin_web/server.py" ] && cp "$backup_dir/admin_web/server.py" "$ADMIN_WEB_DIR/server.py" 2>/dev/null
        [ -d "$backup_dir/admin_web/static" ] && cp -a "$backup_dir/admin_web/static" "$ADMIN_WEB_DIR/" 2>/dev/null
        rm -f "$ADMIN_WEB_DIR/token" 2>/dev/null || true
        log_success "Конфигурация web-админки восстановлена"
    fi

    # Запускаем сервисы
    if is_telemt_installed && [ ! -f "/etc/systemd/system/${TELEMT_SERVICE}.service" ]; then
        install_telemt_service
    fi
    if is_telemt_installed; then
        start_telemt
    fi
    command -v nginx &>/dev/null && systemctl start nginx 2>/dev/null
    systemctl restart gotelegram-bot 2>/dev/null || true
    systemctl restart gotelegram-admin 2>/dev/null || true

    # Очистка
    backup_secure_cleanup "$tmp_dir"

    log_success "$(_t_or backup_restore_done 'Восстановление завершено!')"
    show_proxy_info
    return 0
}

# ── Список бекапов ───────────────────────────────────────────────────────────
list_backups() {
    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        log_info "$(_t_or backup_none 'Бекапов нет')"
        return 1
    fi

    echo ""
    echo -e "  ${BOLD}${WHITE}📦 $(_t_or backup_list_title 'Доступные бекапы'):${NC}"
    echo -e "  ${DIM}$(printf '─%.0s' {1..60})${NC}"

    local i=1
    for f in "$BACKUP_DIR"/*.tar.gz*; do
        [ -f "$f" ] || continue
        [[ "$f" == *.sha256 ]] && continue
        local size date_str name
        size=$(du -h "$f" | cut -f1)
        name=$(basename "$f")
        date_str=$(echo "$name" | grep -oE '[0-9]{8}_[0-9]{6}' | head -1)
        local encrypted=""
        [[ "$f" == *.enc ]] && encrypted=" 🔒"
        echo -e "  ${CYAN}${i})${NC} ${name} (${size})${encrypted}"
        ((i++))
    done
    echo -e "  ${DIM}$(printf '─%.0s' {1..60})${NC}"
}

# ── Очистка старых бекапов ───────────────────────────────────────────────────
cleanup_old_backups() {
    local keep="${1:-5}"
    local count
    count=$(find "$BACKUP_DIR" -name "*.tar.gz*" ! -name "*.sha256" 2>/dev/null | wc -l)

    if [ "$count" -gt "$keep" ]; then
        local to_delete=$((count - keep))
        find "$BACKUP_DIR" -name "*.tar.gz*" ! -name "*.sha256" 2>/dev/null | sort | head -n "$to_delete" | while read -r f; do
            rm -f "$f" "${f}.sha256"
        done
        if type tf &>/dev/null; then
            log_dim "$(tf backup_cleanup_fmt "$to_delete" "$keep")"
        else
            log_dim "Удалено $to_delete старых бекапов (оставлено $keep)"
        fi
    fi
}

# ── Расписание бекапов ───────────────────────────────────────────────────────
backup_schedule_calendar() {
    case "${1:-off}" in
        off) echo "" ;;
        daily) echo "*-*-* 03:20:00" ;;
        weekly) echo "Sun 03:20:00" ;;
        monthly) echo "*-*-01 03:20:00" ;;
        *) return 1 ;;
    esac
}

set_backup_schedule() {
    local frequency="${1:-off}"
    local calendar
    if ! calendar=$(backup_schedule_calendar "$frequency"); then
        log_error "Unsupported backup schedule: $frequency"
        return 1
    fi

    mkdir -p "$GOTELEGRAM_DIR" "$BACKUP_DIR"

    if [ "$frequency" = "off" ]; then
        systemctl disable --now gotelegram-backup.timer >/dev/null 2>&1 || true
        rm -f /etc/systemd/system/gotelegram-backup.timer /etc/systemd/system/gotelegram-backup.service
        systemctl daemon-reload >/dev/null 2>&1 || true
    else
        if ! command -v gpg >/dev/null 2>&1; then
            log_error "Для плановых защищённых бэкапов установите пакет gnupg"
            return 1
        fi
        if [ ! -f "$BACKUP_PASSPHRASE_FILE" ]; then
            ensure_backup_passphrase_file || return 1
            log_info "Создан отдельный ключ плановых бэкапов: $BACKUP_PASSPHRASE_FILE"
            log_info "Скопируйте этот ключ в безопасное место отдельно от VPS."
        fi
        cat > /etc/systemd/system/gotelegram-backup.service << 'EOSVC'
[Unit]
Description=goTelegram Pro backup
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
Environment=GOTELEGRAM_BACKUP_KEEP=30
ExecStart=/bin/bash -lc 'source /opt/gotelegram/current/lib/common.sh; source /opt/gotelegram/current/lib/i18n.sh; source /opt/gotelegram/current/lib/telemt.sh; source /opt/gotelegram/current/lib/website.sh; source /opt/gotelegram/current/lib/backup.sh; load_language ru; create_backup_from_password_file; cleanup_old_backups "${GOTELEGRAM_BACKUP_KEEP:-30}"'
EOSVC

        cat > /etc/systemd/system/gotelegram-backup.timer << EOTIMER
[Unit]
Description=goTelegram Pro scheduled backup

[Timer]
OnCalendar=$calendar
Persistent=true
RandomizedDelaySec=15m
Unit=gotelegram-backup.service

[Install]
WantedBy=timers.target
EOTIMER
        systemctl daemon-reload >/dev/null 2>&1 || return 1
        systemctl enable --now gotelegram-backup.timer >/dev/null 2>&1 || return 1
    fi

    cat > "$GOTELEGRAM_DIR/backup_schedule.json" << EOSCHEDULE
{
    "frequency": "$frequency",
    "calendar": "$calendar",
    "keep": 30,
    "updated_at": "$(date -Iseconds)"
}
EOSCHEDULE
    chmod 600 "$GOTELEGRAM_DIR/backup_schedule.json" 2>/dev/null || true
    log_success "Backup schedule: $frequency"
    echo "$frequency"
}

backup_schedule_status() {
    local frequency="off" calendar=""
    if [ -f "$GOTELEGRAM_DIR/backup_schedule.json" ] && command -v jq >/dev/null 2>&1; then
        frequency=$(jq -r '.frequency // "off"' "$GOTELEGRAM_DIR/backup_schedule.json" 2>/dev/null || echo "off")
        calendar=$(jq -r '.calendar // ""' "$GOTELEGRAM_DIR/backup_schedule.json" 2>/dev/null || echo "")
    fi
    echo "frequency=$frequency calendar=$calendar"
    systemctl list-timers gotelegram-backup.timer --no-pager 2>/dev/null || true
}

# ── Интерактивный бекап ──────────────────────────────────────────────────────
interactive_backup() {
    echo ""
    echo -e "  ${BOLD}${WHITE}💾 $(_t_or backup_create_title 'Создание бекапа')${NC}"
    echo -ne "  $(_t_or backup_encrypt_prompt 'Зашифровать бекап паролем?') [Y/n]: "
    read -r use_pass

    local password=""
    if [[ ! "$use_pass" =~ ^[Nn] ]]; then
        echo -ne "  $(_t_or backup_enter_pass 'Введите пароль'): "
        read -rs password
        echo ""
        echo -ne "  $(_t_or backup_repeat_pass 'Повторите пароль'): "
        read -rs password2
        echo ""
        if [ "$password" != "$password2" ]; then
            log_error "$(_t_or backup_pass_mismatch 'Пароли не совпадают')"
            return 1
        fi
        if [ ${#password} -lt 6 ]; then
            log_error "$(_t_or backup_pass_short 'Пароль слишком короткий (минимум 6 символов)')"
            return 1
        fi
    fi

    create_backup "$password"
    cleanup_old_backups
}

# ── Интерактивное восстановление ─────────────────────────────────────────────
interactive_restore() {
    list_backups || return 1

    echo -ne "  $(_t_or backup_pick_prompt 'Номер бекапа (или путь к файлу)'): "
    read -r choice

    local backup_file=""
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
        local i=1
        for f in "$BACKUP_DIR"/*.tar.gz*; do
            [ -f "$f" ] || continue
            [[ "$f" == *.sha256 ]] && continue
            if [ "$i" -eq "$choice" ]; then
                backup_file="$f"
                break
            fi
            ((i++))
        done
    elif [ -f "$choice" ]; then
        backup_file="$choice"
    fi

    if [ -z "$backup_file" ]; then
        log_error "$(_t_or backup_not_found 'Бекап не найден')"
        return 1
    fi

    restore_backup "$backup_file"
}
