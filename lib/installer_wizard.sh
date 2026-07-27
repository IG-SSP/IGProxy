#!/bin/bash
# goTelegram Clean — безопасный русский мастер установки.
# Все функции preflight до явного подтверждения работают только на чтение.

INSTALLER_PORT_CANDIDATES="${INSTALLER_PORT_CANDIDATES:-8443 9443 2053}"
INSTALLER_SELECTED_PORT="${INSTALLER_SELECTED_PORT:-}"
INSTALLER_INTERNAL_PORT="${INSTALLER_INTERNAL_PORT:-}"
INSTALLER_PREFLIGHT_FATAL=0

installer_trim_line() {
    printf '%s' "${1:-}" | tr '\n\r\t' '   ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//' | cut -c1-120
}

installer_port_listener() {
    local port="$1" line=""
    if command -v ss >/dev/null 2>&1; then
        line=$(ss -H -ltnp "sport = :${port}" 2>/dev/null | head -1)
        [ -z "$line" ] && line=$(ss -H -ltnp 2>/dev/null | awk -v p=":${port}" '$4 ~ p"$" {print; exit}')
    fi
    if [ -z "$line" ] && command -v netstat >/dev/null 2>&1; then
        line=$(netstat -tlnp 2>/dev/null | awk -v p=":${port}" '$4 ~ p"$" {print; exit}')
    fi
    installer_trim_line "$line"
}

installer_existing_public_port() {
    local port=""
    if [ -f "${TELEMT_CONFIG:-/etc/telemt/config.toml}" ] && type get_config_value >/dev/null 2>&1; then
        port=$(get_config_value port "${TELEMT_CONFIG:-/etc/telemt/config.toml}" 2>/dev/null || true)
    fi
    if [ -z "$port" ] && [ -f "${GOTELEGRAM_CONFIG:-/opt/gotelegram/config.json}" ] && command -v jq >/dev/null 2>&1; then
        port=$(jq -r '.port // empty' "${GOTELEGRAM_CONFIG:-/opt/gotelegram/config.json}" 2>/dev/null || true)
    fi
    [[ "$port" =~ ^[0-9]+$ ]] && printf '%s\n' "$port"
}

installer_listener_is_ours() {
    local port="$1" listener="${2:-}"
    [ -n "$listener" ] || return 1
    printf '%s' "$listener" | grep -Eiq 'telemt' || return 1
    local existing
    existing=$(installer_existing_public_port)
    [ -n "$existing" ] && [ "$existing" = "$port" ]
}

installer_port_is_usable() {
    local port="$1" listener
    [[ "$port" =~ ^[0-9]+$ ]] || return 1
    [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || return 1
    listener=$(installer_port_listener "$port")
    [ -z "$listener" ] && return 0
    installer_listener_is_ours "$port" "$listener"
}

installer_pick_recommended_port() {
    local existing candidate
    existing=$(installer_existing_public_port)
    if [ -n "$existing" ] && installer_port_is_usable "$existing"; then
        printf '%s\n' "$existing"
        return 0
    fi
    if installer_port_is_usable 443; then
        printf '443\n'
        return 0
    fi
    for candidate in $INSTALLER_PORT_CANDIDATES; do
        if installer_port_is_usable "$candidate"; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

installer_pick_internal_port() {
    local public_port="$1" candidate
    for candidate in 8443 9443 10443 11443; do
        [ "$candidate" = "$public_port" ] && continue
        if installer_port_is_usable "$candidate"; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

installer_port_owner_label() {
    local port="$1" listener
    listener=$(installer_port_listener "$port")
    if [ -z "$listener" ]; then
        printf 'свободен'
    elif installer_listener_is_ours "$port" "$listener"; then
        printf 'наш telemt (обновление)'
    else
        printf '%s' "$listener"
    fi
}

installer_memory_mb() {
    awk '/^MemTotal:/ {print int($2/1024); exit}' /proc/meminfo 2>/dev/null || printf '0\n'
}

installer_disk_free_mb() {
    df -Pm / 2>/dev/null | awk 'NR==2 {print $4; exit}'
}

installer_inode_free_percent() {
    df -Pi / 2>/dev/null | awk 'NR==2 {gsub("%","",$5); print 100-$5; exit}'
}

installer_os_label() {
    if [ -r /etc/os-release ]; then
        sed -n 's/^PRETTY_NAME=//p' /etc/os-release | head -1 | tr -d '"'
    else
        uname -s
    fi
}

installer_os_id() {
    sed -n 's/^ID=//p' /etc/os-release 2>/dev/null | head -1 | tr -d '"'
}

installer_reserved_port_status() {
    local port="$1" service="$2" listener
    listener=$(installer_port_listener "$port")
    if [ -z "$listener" ]; then
        printf 'свободен'
        return 0
    fi
    if command -v systemctl >/dev/null 2>&1 &&
       systemctl is-active --quiet "$service" 2>/dev/null &&
       printf '%s' "$listener" | grep -Eq "(^|[[:space:]])(127\\.0\\.0\\.1|\\[?::1\\]?):${port}([[:space:]]|$)"; then
        printf 'занят нашей службой %s' "$service"
        return 0
    fi
    printf 'КОНФЛИКТ или публичная привязка: %s' "$listener"
    return 1
}

installer_firewall_label() {
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
        printf 'ufw активен — после выбора порт будет проверен отдельно'
    elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state 2>/dev/null | grep -q running; then
        printf 'firewalld активен — после выбора порт будет проверен отдельно'
    elif command -v nft >/dev/null 2>&1 && nft list ruleset 2>/dev/null | grep -qE 'hook input'; then
        printf 'nftables обнаружен'
    else
        printf 'активный локальный firewall не обнаружен'
    fi
}

installer_selinux_label() {
    if ! command -v getenforce >/dev/null 2>&1; then
        printf 'не установлен'
        return 0
    fi
    case "$(getenforce 2>/dev/null || true)" in
        Enforcing) printf 'Enforcing — порт сайта будет разрешён точечным правилом' ;;
        Permissive) printf 'Permissive' ;;
        Disabled) printf 'отключён' ;;
        *) printf 'состояние не определено' ;;
    esac
}

installer_selinux_type_allows_port() {
    local type_name="$1" port="$2"
    command -v semanage >/dev/null 2>&1 || return 1
    [[ "$port" =~ ^[0-9]+$ ]] || return 1
    LC_ALL=C semanage port -l 2>/dev/null | awk -v wanted_type="$type_name" -v wanted_port="$port" '
        $1 == wanted_type && $2 == "tcp" {
            for (i = 3; i <= NF; i++) {
                value = $i
                gsub(/,/, "", value)
                split(value, bounds, "-")
                if ((bounds[2] == "" && bounds[1] == wanted_port) ||
                    (bounds[2] != "" && wanted_port >= bounds[1] && wanted_port <= bounds[2])) {
                    found = 1
                }
            }
        }
        END { exit(found ? 0 : 1) }
    '
}

installer_prepare_selinux_http_port() {
    local port="$1" pkg_mgr
    [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || {
        log_error "Некорректный внутренний порт для SELinux: $port"
        return 1
    }
    command -v getenforce >/dev/null 2>&1 || return 0
    [ "$(getenforce 2>/dev/null || true)" = "Enforcing" ] || return 0

    if ! command -v semanage >/dev/null 2>&1; then
        pkg_mgr=$(get_pkg_manager)
        log_info "Установка утилиты SELinux для точечного разрешения TCP/${port}..."
        case "$pkg_mgr" in
            dnf) dnf install -y -q policycoreutils-python-utils ;;
            yum) yum install -y -q policycoreutils-python-utils ;;
            *)
                log_error "SELinux работает в Enforcing, но semanage отсутствует."
                return 1
                ;;
        esac
    fi
    command -v semanage >/dev/null 2>&1 || {
        log_error "Не удалось установить semanage; nginx не получит доступ к TCP/${port}."
        return 1
    }
    installer_selinux_type_allows_port http_port_t "$port" && return 0

    if ! semanage port -a -t http_port_t -p tcp "$port" >/dev/null 2>&1; then
        log_error "SELinux не разрешил nginx слушать TCP/${port}; возможно, порт закреплён за другим типом."
        return 1
    fi
    printf '%s\n' "$port" >> "$INSTALLER_TX_DIR/selinux-http-ports.manifest"
    log_success "SELinux: TCP/${port} разрешён только для http_port_t."
}

installer_preflight_collect() {
    INSTALLER_PREFLIGHT_FATAL=0
    INSTALLER_PF_OS=$(installer_os_label)
    INSTALLER_PF_OS_ID=$(installer_os_id)
    INSTALLER_PF_ARCH=$(get_arch 2>/dev/null || uname -m)
    INSTALLER_PF_MEMORY_MB=$(installer_memory_mb)
    INSTALLER_PF_DISK_MB=$(installer_disk_free_mb)
    INSTALLER_PF_INODE_FREE=$(installer_inode_free_percent)
    INSTALLER_PF_IP=$(get_server_ip 2>/dev/null || printf '0.0.0.0')
    INSTALLER_PF_PORT80=$(installer_port_owner_label 80)
    INSTALLER_PF_PORT443=$(installer_port_owner_label 443)
    INSTALLER_PF_RECOMMENDED_PORT=$(installer_pick_recommended_port 2>/dev/null || true)
    INSTALLER_PF_FIREWALL=$(installer_firewall_label)
    INSTALLER_PF_SELINUX=$(installer_selinux_label)
    INSTALLER_PF_ADMIN=$(installer_reserved_port_status 1984 gotelegram-admin) || INSTALLER_PREFLIGHT_FATAL=$((INSTALLER_PREFLIGHT_FATAL + 1))
    INSTALLER_PF_METRICS=$(installer_reserved_port_status 9090 telemt) || INSTALLER_PREFLIGHT_FATAL=$((INSTALLER_PREFLIGHT_FATAL + 1))
    INSTALLER_PF_API=$(installer_reserved_port_status 9091 telemt) || INSTALLER_PREFLIGHT_FATAL=$((INSTALLER_PREFLIGHT_FATAL + 1))
    INSTALLER_PF_EXISTING="нет"
    [ -f "${GOTELEGRAM_CONFIG:-/opt/gotelegram/config.json}" ] && INSTALLER_PF_EXISTING="да, настройки будут сохранены"

    [ "$(id -u)" -eq 0 ] || INSTALLER_PREFLIGHT_FATAL=$((INSTALLER_PREFLIGHT_FATAL + 1))
    [ -f /etc/os-release ] || INSTALLER_PREFLIGHT_FATAL=$((INSTALLER_PREFLIGHT_FATAL + 1))
    case "$INSTALLER_PF_OS_ID" in
        ubuntu|debian|centos|rocky|almalinux|fedora|rhel) ;;
        *) INSTALLER_PREFLIGHT_FATAL=$((INSTALLER_PREFLIGHT_FATAL + 1)) ;;
    esac
    command -v systemctl >/dev/null 2>&1 || INSTALLER_PREFLIGHT_FATAL=$((INSTALLER_PREFLIGHT_FATAL + 1))
    { command -v ss >/dev/null 2>&1 || command -v netstat >/dev/null 2>&1; } || INSTALLER_PREFLIGHT_FATAL=$((INSTALLER_PREFLIGHT_FATAL + 1))
    command -v flock >/dev/null 2>&1 || INSTALLER_PREFLIGHT_FATAL=$((INSTALLER_PREFLIGHT_FATAL + 1))
    case "$INSTALLER_PF_ARCH" in amd64|arm64) ;; *) INSTALLER_PREFLIGHT_FATAL=$((INSTALLER_PREFLIGHT_FATAL + 1)) ;; esac
    [ "${INSTALLER_PF_DISK_MB:-0}" -ge 500 ] 2>/dev/null || INSTALLER_PREFLIGHT_FATAL=$((INSTALLER_PREFLIGHT_FATAL + 1))
    [ "${INSTALLER_PF_INODE_FREE:-0}" -ge 5 ] 2>/dev/null || INSTALLER_PREFLIGHT_FATAL=$((INSTALLER_PREFLIGHT_FATAL + 1))
    [ -n "$INSTALLER_PF_RECOMMENDED_PORT" ] || INSTALLER_PREFLIGHT_FATAL=$((INSTALLER_PREFLIGHT_FATAL + 1))
}

installer_status_line() {
    local level="$1" title="$2" value="$3" icon color
    case "$level" in
        ok) icon="✓"; color="${GREEN:-}" ;;
        warn) icon="!"; color="${YELLOW:-}" ;;
        *) icon="✗"; color="${RED:-}" ;;
    esac
    printf '  %b%-2s%b %-22s %s\n' "$color" "$icon" "${NC:-}" "$title" "$value"
}

installer_preflight_show() {
    echo ""
    echo -e "  ${BOLD:-}Проверка сервера перед установкой${NC:-}"
    echo -e "  ${DIM:-}$(printf '─%.0s' {1..64})${NC:-}"
    installer_status_line ok "Система" "$INSTALLER_PF_OS · $INSTALLER_PF_ARCH"
    if [ "${INSTALLER_PF_MEMORY_MB:-0}" -lt 256 ] 2>/dev/null; then
        installer_status_line warn "Память" "${INSTALLER_PF_MEMORY_MB} MB (рекомендуется от 256 MB)"
    else
        installer_status_line ok "Память" "${INSTALLER_PF_MEMORY_MB} MB"
    fi
    if [ "${INSTALLER_PF_DISK_MB:-0}" -lt 500 ] 2>/dev/null; then
        installer_status_line error "Свободное место" "${INSTALLER_PF_DISK_MB} MB (нужно минимум 500 MB)"
    else
        installer_status_line ok "Свободное место" "${INSTALLER_PF_DISK_MB} MB"
    fi
    if [ "${INSTALLER_PF_INODE_FREE:-0}" -lt 5 ] 2>/dev/null; then
        installer_status_line error "Свободные inode" "${INSTALLER_PF_INODE_FREE}% (нужно минимум 5%)"
    else
        installer_status_line ok "Свободные inode" "${INSTALLER_PF_INODE_FREE}%"
    fi
    if [ "$INSTALLER_PF_IP" = "0.0.0.0" ] || [ -z "$INSTALLER_PF_IP" ]; then
        installer_status_line warn "Публичный IPv4" "не удалось определить"
    else
        installer_status_line ok "Публичный IPv4" "$INSTALLER_PF_IP"
    fi
    installer_status_line ok "Порт 80" "$INSTALLER_PF_PORT80"
    if installer_port_is_usable 443; then
        installer_status_line ok "Порт 443" "$INSTALLER_PF_PORT443"
    else
        installer_status_line warn "Порт 443" "$INSTALLER_PF_PORT443"
    fi
    if [ -n "$INSTALLER_PF_RECOMMENDED_PORT" ]; then
        installer_status_line ok "Порт для прокси" "$INSTALLER_PF_RECOMMENDED_PORT"
    else
        installer_status_line error "Порт для прокси" "443, 8443, 9443 и 2053 заняты"
    fi
    installer_status_line ok "Firewall" "$INSTALLER_PF_FIREWALL"
    case "$INSTALLER_PF_SELINUX" in
        Enforcing*) installer_status_line warn "SELinux" "$INSTALLER_PF_SELINUX" ;;
        *) installer_status_line ok "SELinux" "$INSTALLER_PF_SELINUX" ;;
    esac
    case "$INSTALLER_PF_ADMIN" in КОНФЛИКТ*) installer_status_line error "Админка 127.0.0.1:1984" "$INSTALLER_PF_ADMIN" ;; *) installer_status_line ok "Админка 127.0.0.1:1984" "$INSTALLER_PF_ADMIN" ;; esac
    case "$INSTALLER_PF_METRICS" in КОНФЛИКТ*) installer_status_line error "Метрики 127.0.0.1:9090" "$INSTALLER_PF_METRICS" ;; *) installer_status_line ok "Метрики 127.0.0.1:9090" "$INSTALLER_PF_METRICS" ;; esac
    case "$INSTALLER_PF_API" in КОНФЛИКТ*) installer_status_line error "API 127.0.0.1:9091" "$INSTALLER_PF_API" ;; *) installer_status_line ok "API 127.0.0.1:9091" "$INSTALLER_PF_API" ;; esac
    installer_status_line ok "Существующая установка" "$INSTALLER_PF_EXISTING"
    echo -e "  ${DIM:-}$(printf '─%.0s' {1..64})${NC:-}"
}

installer_preflight_run() {
    installer_preflight_collect
    installer_preflight_show
    if [ "$INSTALLER_PREFLIGHT_FATAL" -gt 0 ]; then
        log_error "Сервер пока не готов к безопасной установке. Исправьте пункты с ✗ и запустите мастер снова."
        return 1
    fi
    return 0
}

installer_json_escape() {
    printf '%s' "${1:-}" | tr '\r\n' '  ' | sed \
        -e 's/\\/\\\\/g' \
        -e 's/"/\\"/g'
}

installer_preflight_json() {
    installer_preflight_collect
    printf '{'
    printf '"ready":%s,' "$([ "$INSTALLER_PREFLIGHT_FATAL" -eq 0 ] && printf true || printf false)"
    printf '"fatal_count":%s,' "$INSTALLER_PREFLIGHT_FATAL"
    printf '"os":"%s",' "$(installer_json_escape "$INSTALLER_PF_OS")"
    printf '"arch":"%s",' "$(installer_json_escape "$INSTALLER_PF_ARCH")"
    printf '"memory_mb":%s,' "${INSTALLER_PF_MEMORY_MB:-0}"
    printf '"disk_free_mb":%s,' "${INSTALLER_PF_DISK_MB:-0}"
    printf '"inode_free_percent":%s,' "${INSTALLER_PF_INODE_FREE:-0}"
    printf '"public_ip":"%s",' "$(installer_json_escape "$INSTALLER_PF_IP")"
    printf '"port_80":"%s",' "$(installer_json_escape "$INSTALLER_PF_PORT80")"
    printf '"port_443":"%s",' "$(installer_json_escape "$INSTALLER_PF_PORT443")"
    printf '"recommended_proxy_port":"%s",' "$(installer_json_escape "$INSTALLER_PF_RECOMMENDED_PORT")"
    printf '"admin_port":"%s",' "$(installer_json_escape "$INSTALLER_PF_ADMIN")"
    printf '"metrics_port":"%s",' "$(installer_json_escape "$INSTALLER_PF_METRICS")"
    printf '"api_port":"%s",' "$(installer_json_escape "$INSTALLER_PF_API")"
    printf '"firewall":"%s",' "$(installer_json_escape "$INSTALLER_PF_FIREWALL")"
    printf '"selinux":"%s",' "$(installer_json_escape "$INSTALLER_PF_SELINUX")"
    printf '"existing_install":"%s"' "$(installer_json_escape "$INSTALLER_PF_EXISTING")"
    printf '}\n'
    [ "$INSTALLER_PREFLIGHT_FATAL" -eq 0 ]
}

installer_choose_public_port() {
    local recommended choice custom owner
    recommended="${INSTALLER_SELECTED_PORT:-}"
    [ -n "$recommended" ] || recommended=$(installer_pick_recommended_port) || {
        log_error "Не найден свободный порт для прокси."
        return 1
    }
    while true; do
        echo "" >&2
        echo -e "  ${BOLD:-}Публичный порт прокси${NC:-}" >&2
        echo -e "  ${GREEN:-}1)${NC:-} ${recommended} — рекомендуется" >&2
        echo -e "  ${CYAN:-}2)${NC:-} Указать другой порт" >&2
        echo -e "  ${DIM:-}0) Отмена${NC:-}" >&2
        echo -ne "  Выбор [1]: " >&2
        read -r choice
        case "${choice:-1}" in
            1)
                INSTALLER_SELECTED_PORT="$recommended"
                printf '%s\n' "$recommended"
                return 0
                ;;
            2)
                echo -ne "  Порт (1–65535): " >&2
                read -r custom
                if ! [[ "$custom" =~ ^[0-9]+$ ]] || [ "$custom" -lt 1 ] || [ "$custom" -gt 65535 ]; then
                    log_error "Некорректный номер порта."
                    continue
                fi
                if ! installer_port_is_usable "$custom"; then
                    owner=$(installer_port_owner_label "$custom")
                    log_error "Порт $custom уже занят: $owner"
                    continue
                fi
                INSTALLER_SELECTED_PORT="$custom"
                printf '%s\n' "$custom"
                return 0
                ;;
            0) return 1 ;;
            *) log_warning "Выберите 1, 2 или 0." ;;
        esac
    done
}

installer_domain_a_records() {
    dig +short A "$1" 2>/dev/null | grep -E '^[0-9.]+$' | sort -u
}

installer_domain_aaaa_records() {
    dig +short AAAA "$1" 2>/dev/null | grep -E '^[0-9a-fA-F:]+$' | sort -u
}

installer_local_global_ipv6() {
    ip -6 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1
}

installer_domain_preflight() {
    local domain="$1" server_ip records aaaa local_v6 owner80 caa public_records resolver
    validate_domain "$domain" || {
        log_error "Некорректный домен: $domain"
        return 1
    }
    command -v dig >/dev/null 2>&1 || {
        log_error "Для проверки DNS нужна утилита dig (пакет dnsutils/bind-utils). Установите её и запустите мастер снова."
        return 1
    }
    server_ip=$(get_server_ip 2>/dev/null || true)
    records=$(installer_domain_a_records "$domain")
    echo ""
    echo -e "  ${BOLD:-}Проверка домена ${domain}${NC:-}"
    if [ -z "$records" ]; then
        log_error "A-запись домена ещё не видна. Создайте запись на IP ${server_ip:-этого сервера} и дождитесь распространения DNS."
        return 1
    fi
    if [ -z "$server_ip" ] || ! printf '%s\n' "$records" | grep -Fxq "$server_ip"; then
        log_error "A-запись ведёт на другой сервер: $(installer_trim_line "$records"). Ожидается: ${server_ip:-не удалось определить}."
        return 1
    fi
    log_success "A-запись совпадает с IP сервера: $server_ip"

    for resolver in 1.1.1.1 8.8.8.8; do
        public_records=$(dig +time=2 +tries=1 +short "@$resolver" A "$domain" 2>/dev/null | grep -E '^[0-9.]+$' | sort -u)
        [ -z "$public_records" ] && continue
        if ! printf '%s\n' "$public_records" | grep -Fxq "$server_ip"; then
            log_error "Публичный DNS-резолвер $resolver ещё видит другой IP: $(installer_trim_line "$public_records"). Дождитесь распространения DNS."
            return 1
        fi
    done
    log_success "Публичные DNS-резолверы видят правильный IPv4."

    aaaa=$(installer_domain_aaaa_records "$domain")
    if [ -n "$aaaa" ]; then
        local_v6=$(installer_local_global_ipv6)
        if [ -z "$local_v6" ] || ! printf '%s\n' "$aaaa" | grep -Fxiq "$local_v6"; then
            log_error "У домена есть AAAA-запись ($(installer_trim_line "$aaaa")), но сервер не владеет этим IPv6. Let's Encrypt может прийти по неверному адресу."
            return 1
        fi
        log_success "AAAA-запись совпадает с IPv6 сервера."
    else
        log_dim "AAAA-записи нет — это нормально для IPv4-сервера."
    fi

    caa=$(dig +short CAA "$domain" 2>/dev/null || true)
    if [ -n "$caa" ] && printf '%s\n' "$caa" | grep -Eq '[[:space:]]issue[[:space:]]' && \
       ! printf '%s\n' "$caa" | grep -Eiq 'letsencrypt\.org'; then
        log_error "CAA запрещает выпуск сертификата Let's Encrypt: $(installer_trim_line "$caa")."
        return 1
    fi
    [ -n "$caa" ] && log_success "CAA допускает Let's Encrypt." || log_dim "CAA-записей нет — выпуск Let's Encrypt не ограничен."

    owner80=$(installer_port_listener 80)
    if [ -n "$owner80" ] && ! printf '%s' "$owner80" | grep -Eiq 'nginx'; then
        log_error "TCP/80 занят не nginx: $(installer_trim_line "$owner80"). Webroot-проверка Let's Encrypt небезопасна."
        return 1
    fi
    if [ -n "$owner80" ]; then
        log_success "Порт 80 уже обслуживает nginx; мастер добавит отдельный server_name."
    else
        log_success "Порт 80 свободен для проверки Let's Encrypt."
    fi
    return 0
}

installer_choose_mode() {
    local choice
    echo "" >&2
    echo -e "  ${BOLD:-}Что установить?${NC:-}" >&2
    echo -e "  ${CYAN:-}1)${NC:-} ${BOLD:-}Свой домен и сайт${NC:-}" >&2
    echo -e "     ${DIM:-}Прокси маскируется под ваш HTTPS-сайт. Нужны готовые DNS-записи.${NC:-}" >&2
    echo -e "  ${CYAN:-}2)${NC:-} ${BOLD:-}Только прокси${NC:-}" >&2
    echo -e "     ${DIM:-}Без сайта и сертификата. Лучше для серверов с уже занятым 443.${NC:-}" >&2
    echo -e "  ${DIM:-}0) Отмена${NC:-}" >&2
    echo -ne "  Выбор [2]: " >&2
    read -r choice
    case "${choice:-2}" in
        1) printf 'pro\n' ;;
        2) printf 'lite\n' ;;
        0) return 1 ;;
        *) log_error "Выберите 1, 2 или 0."; return 1 ;;
    esac
}

installer_show_apply_plan() {
    local mode="$1" public_port="$2" domain="${3:-}" internal_port="${4:-}"
    echo ""
    echo -e "  ${BOLD:-}План изменений${NC:-}"
    echo -e "  ${DIM:-}$(printf '─%.0s' {1..64})${NC:-}"
    echo "  • При необходимости установить недостающие системные пакеты."
    echo "  • Установить проверенную версию telemt и systemd-службу telemt."
    echo "  • Записать /etc/telemt/config.toml и /opt/gotelegram/config.json."
    echo "  • Открыть telemt на TCP/${public_port}; занятые службы не перемещаются."
    if [ "$mode" = "pro" ]; then
        echo "  • Настроить домен ${domain}, сертификат Let's Encrypt и сайт."
        echo "  • Добавить отдельный nginx server_name на TCP/80."
        echo "  • Сайт маскировки слушает только 127.0.0.1:${internal_port}."
        echo "  • При SELinux Enforcing точечно разрешить nginx TCP/${internal_port}."
    else
        echo "  • nginx, сайты и сертификаты не изменяются."
    fi
    echo "  • Админка при установке останется только на 127.0.0.1:1984."
    echo "  • Firewall, sysctl и глобальные настройки journald НЕ изменяются."
    echo "  • Перед применением будет создан root-only rollback-снимок."
    echo -e "  ${DIM:-}$(printf '─%.0s' {1..64})${NC:-}"
}

INSTALLER_TX_DIR="${INSTALLER_TX_DIR:-}"
INSTALLER_TX_DOMAIN="${INSTALLER_TX_DOMAIN:-}"

installer_lock_acquire() {
    command -v flock >/dev/null 2>&1 || {
        log_error "flock не найден; невозможно защититься от параллельного запуска."
        return 1
    }
    mkdir -p /run/lock 2>/dev/null || return 1
    exec 8>/run/lock/gotelegram-installer.lock
    flock -n 8 || {
        log_error "Другой экземпляр установщика уже работает."
        exec 8>&-
        return 1
    }
}

installer_tx_copy_if_exists() {
    local path="$1" root="$INSTALLER_TX_DIR/rootfs"
    if [ -e "$path" ] || [ -L "$path" ]; then
        mkdir -p "$root$(dirname "$path")"
        cp -a "$path" "$root$path"
        printf 'present %s\n' "$path" >> "$INSTALLER_TX_DIR/files.manifest"
    else
        printf 'absent %s\n' "$path" >> "$INSTALLER_TX_DIR/files.manifest"
    fi
}

installer_tx_service_state() {
    local service="$1" active=inactive enabled=disabled
    systemctl is-active --quiet "$service" 2>/dev/null && active=active
    systemctl is-enabled --quiet "$service" 2>/dev/null && enabled=enabled
    printf '%s %s %s\n' "$service" "$active" "$enabled" >> "$INSTALLER_TX_DIR/services.manifest"
}

installer_transaction_begin() {
    local profile="${1:-unknown}" stamp
    installer_lock_acquire || return 1
    umask 077
    stamp=$(date +%Y%m%d_%H%M%S)
    INSTALLER_TX_DIR="/var/lib/gotelegram-installer/transactions/${stamp}-$$"
    mkdir -p "$INSTALLER_TX_DIR/rootfs" || {
        exec 8>&-
        return 1
    }
    chmod 700 /var/lib/gotelegram-installer /var/lib/gotelegram-installer/transactions "$INSTALLER_TX_DIR" 2>/dev/null || true
    printf 'profile=%s\nstarted_at=%s\n' "$profile" "$(date -Iseconds)" > "$INSTALLER_TX_DIR/meta"
    : > "$INSTALLER_TX_DIR/files.manifest"
    : > "$INSTALLER_TX_DIR/services.manifest"
    : > "$INSTALLER_TX_DIR/selinux-http-ports.manifest"

    installer_tx_copy_if_exists "${TELEMT_CONFIG:-/etc/telemt/config.toml}"
    installer_tx_copy_if_exists "${GOTELEGRAM_CONFIG:-/opt/gotelegram/config.json}"
    installer_tx_copy_if_exists "${TELEMT_BIN:-/usr/local/bin/telemt}"
    installer_tx_copy_if_exists "${NGINX_SITE_CONF:-/etc/nginx/sites-available/gotelegram}"
    installer_tx_copy_if_exists "${NGINX_SITE_LINK:-/etc/nginx/sites-enabled/gotelegram}"
    installer_tx_copy_if_exists /etc/systemd/system/telemt.service
    installer_tx_copy_if_exists /etc/sysctl.d/99-zz-gotelegram.conf
    installer_tx_copy_if_exists /etc/systemd/journald.conf.d/99-gotelegram.conf
    installer_tx_copy_if_exists /etc/rsyslog.d/00-gotelegram-telemt.conf
    installer_tx_copy_if_exists "${WEBSITE_ROOT:-/var/www/gotelegram-site}"
    installer_tx_copy_if_exists /etc/systemd/system/gotelegram-certbot-renew.service
    installer_tx_copy_if_exists /etc/systemd/system/gotelegram-certbot-renew.timer
    if [ -n "$INSTALLER_TX_DOMAIN" ]; then
        validate_domain "$INSTALLER_TX_DOMAIN" || {
            log_error "Некорректный домен для rollback-снимка."
            return 1
        }
        installer_tx_copy_if_exists "/etc/letsencrypt/live/$INSTALLER_TX_DOMAIN"
        installer_tx_copy_if_exists "/etc/letsencrypt/archive/$INSTALLER_TX_DOMAIN"
        installer_tx_copy_if_exists "/etc/letsencrypt/renewal/$INSTALLER_TX_DOMAIN.conf"
    fi

    installer_tx_service_state telemt
    installer_tx_service_state nginx
    installer_tx_service_state gotelegram-admin
    installer_tx_service_state gotelegram-bot
    installer_tx_service_state certbot.timer
    installer_tx_service_state gotelegram-certbot-renew.timer
    chmod -R go-rwx "$INSTALLER_TX_DIR" 2>/dev/null || true
    trap 'installer_transaction_rollback "получен сигнал"; exit 130' INT TERM HUP
    log_success "Создана точка отката: $INSTALLER_TX_DIR"
}

installer_transaction_restore_files() {
    local state path source
    while IFS=' ' read -r state path; do
        [ -n "$path" ] || continue
        case "$path" in
            "${TELEMT_CONFIG:-/etc/telemt/config.toml}"|\
            "${GOTELEGRAM_CONFIG:-/opt/gotelegram/config.json}"|\
            "${TELEMT_BIN:-/usr/local/bin/telemt}"|\
            "${NGINX_SITE_CONF:-/etc/nginx/sites-available/gotelegram}"|\
            "${NGINX_SITE_LINK:-/etc/nginx/sites-enabled/gotelegram}"|\
            "${WEBSITE_ROOT:-/var/www/gotelegram-site}"|\
            /etc/systemd/system/telemt.service|\
            /etc/sysctl.d/99-zz-gotelegram.conf|\
            /etc/systemd/journald.conf.d/99-gotelegram.conf|\
            /etc/rsyslog.d/00-gotelegram-telemt.conf|\
            /etc/systemd/system/gotelegram-certbot-renew.service|\
            /etc/systemd/system/gotelegram-certbot-renew.timer) ;;
            *)
                if [ -n "$INSTALLER_TX_DOMAIN" ]; then
                    case "$path" in
                        "/etc/letsencrypt/live/$INSTALLER_TX_DOMAIN"|\
                        "/etc/letsencrypt/archive/$INSTALLER_TX_DOMAIN"|\
                        "/etc/letsencrypt/renewal/$INSTALLER_TX_DOMAIN.conf") ;;
                        *)
                            log_error "Небезопасный путь в rollback-манифесте: $path"
                            return 1
                            ;;
                    esac
                else
                    log_error "Небезопасный путь в rollback-манифесте: $path"
                    return 1
                fi
                ;;
        esac
        source="$INSTALLER_TX_DIR/rootfs$path"
        if [ "$state" = "present" ]; then
            if [ -d "$source" ] && [ ! -L "$source" ]; then
                rm -rf -- "$path"
                mkdir -p "$(dirname "$path")"
                cp -a "$source" "$path"
            else
                rm -f -- "$path"
                mkdir -p "$(dirname "$path")"
                cp -a "$source" "$path"
            fi
        elif [ "$state" = "absent" ]; then
            if [ -d "$path" ] && [ ! -L "$path" ]; then
                rm -rf -- "$path"
            else
                rm -f -- "$path"
            fi
        fi
    done < "$INSTALLER_TX_DIR/files.manifest"
}

installer_transaction_restore_services() {
    local service active enabled
    systemctl daemon-reload 2>/dev/null || true
    while IFS=' ' read -r service active enabled; do
        [ -n "$service" ] || continue
        if [ "$enabled" = "enabled" ]; then
            systemctl enable "$service" >/dev/null 2>&1 || true
        else
            systemctl disable "$service" >/dev/null 2>&1 || true
        fi
        if [ "$active" = "active" ]; then
            systemctl restart "$service" >/dev/null 2>&1 || true
        else
            systemctl stop "$service" >/dev/null 2>&1 || true
        fi
    done < "$INSTALLER_TX_DIR/services.manifest"
}

installer_transaction_rollback() {
    local reason="${1:-ошибка установки}" restore_ok=1
    trap - INT TERM HUP
    if [ -z "$INSTALLER_TX_DIR" ] || [ ! -d "$INSTALLER_TX_DIR" ]; then
        log_error "Откат невозможен: точка восстановления не найдена."
        exec 8>&- 2>/dev/null || true
        return 1
    fi
    log_warning "Откат изменений: $reason"
    systemctl stop telemt nginx >/dev/null 2>&1 || true
    installer_transaction_restore_files || restore_ok=0
    if [ -f "$INSTALLER_TX_DIR/selinux-http-ports.manifest" ] && command -v semanage >/dev/null 2>&1; then
        local selinux_port
        while IFS= read -r selinux_port; do
            [[ "$selinux_port" =~ ^[0-9]+$ ]] || continue
            semanage port -d -t http_port_t -p tcp "$selinux_port" >/dev/null 2>&1 || restore_ok=0
        done < "$INSTALLER_TX_DIR/selinux-http-ports.manifest"
    fi
    installer_transaction_restore_services
    printf 'rolled_back_at=%s\nreason=%s\n' "$(date -Iseconds)" "$reason" >> "$INSTALLER_TX_DIR/meta"
    chmod -R go-rwx "$INSTALLER_TX_DIR" 2>/dev/null || true
    if [ "$restore_ok" -eq 1 ]; then
        log_success "Предыдущее состояние восстановлено."
    else
        log_error "Rollback остановлен из-за небезопасного манифеста; требуется ручная проверка."
    fi
    exec 8>&- 2>/dev/null || true
    INSTALLER_TX_DIR=""
    INSTALLER_TX_DOMAIN=""
    [ "$restore_ok" -eq 1 ]
}

installer_transaction_commit() {
    trap - INT TERM HUP
    if [ -n "$INSTALLER_TX_DIR" ] && [ -d "$INSTALLER_TX_DIR" ]; then
        printf 'committed_at=%s\n' "$(date -Iseconds)" >> "$INSTALLER_TX_DIR/meta"
        chmod -R go-rwx "$INSTALLER_TX_DIR" 2>/dev/null || true
        log_success "Установка подтверждена. Точка отката сохранена: $INSTALLER_TX_DIR"
    fi
    exec 8>&- 2>/dev/null || true
    INSTALLER_TX_DIR=""
    INSTALLER_TX_DOMAIN=""
}

installer_verify_install() {
    local mode="$1" public_port="$2" domain="${3:-}"
    systemctl is-active --quiet telemt 2>/dev/null || {
        log_error "telemt не запущен после установки."
        return 1
    }
    local listener
    listener=$(installer_port_listener "$public_port")
    printf '%s' "$listener" | grep -Eiq 'telemt' || {
        log_error "telemt не слушает выбранный порт $public_port."
        return 1
    }
    if [ "$mode" = "pro" ]; then
        systemctl is-active --quiet nginx 2>/dev/null || {
            log_error "nginx не запущен после установки."
            return 1
        }
        curl -ksS --max-time 8 --resolve "${domain}:${public_port}:127.0.0.1" \
            "https://${domain}:${public_port}/" -o /dev/null || {
            log_error "Сайт маскировки не отвечает через telemt на порту $public_port."
            return 1
        }
    fi
    local admin_listener reserved_port reserved_listener
    admin_listener=$(installer_port_listener 1984)
    if [ -n "$admin_listener" ] && printf '%s' "$admin_listener" | grep -Eq '(^|[[:space:]])(0\.0\.0\.0|\[::\]|\*):?1984'; then
        log_error "Админка обнаружена на публичном адресе:1984. Установка остановлена."
        return 1
    fi
    for reserved_port in 9090 9091; do
        reserved_listener=$(installer_port_listener "$reserved_port")
        if [ -n "$reserved_listener" ] &&
           ! printf '%s' "$reserved_listener" | grep -Eq "(^|[[:space:]])(127\\.0\\.0\\.1|\\[?::1\\]?):${reserved_port}([[:space:]]|$)"; then
            log_error "Служебный порт $reserved_port доступен не только локально; установка остановлена."
            return 1
        fi
    done
    return 0
}
