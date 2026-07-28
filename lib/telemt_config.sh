#!/bin/bash
# IGProxy v2.13.0 — генерация TOML-конфигурации для telemt

# ── Популярные домены (не заблокированные в РФ) ──────────────────────────────
QUICK_DOMAINS=(
    "google.com"
    "microsoft.com"
    "cloudflare.com"
    "apple.com"
    "amazon.com"
    "github.com"
    "stackoverflow.com"
    "medium.com"
    "wikipedia.org"
    "coursera.org"
    "udemy.com"
    "habr.com"
    "stepik.org"
    "duolingo.com"
    "khanacademy.org"
    "bbc.com"
    "reuters.com"
    "nytimes.com"
    "ted.com"
    "zoom.us"
)

# ── Генерация TOML конфига (telemt v3 формат) ───────────────────────────────
# v2.6.0: добавлены параметры маскировки, отлаженные на тестовом VPS 9 июня 2026 года.
# Стабильно работает с telemt 3.4.15 как через VPN, так и под жёсткий DPI:
#   * client_mss = "92" в [server] — узкий MSS только для handshake
#   * client_mss_bulk = "1400" — нормальный MSS для фото, видео и файлов
#   * mask_shape_hardening + buckets — padding для unknown SNI mask path
#   * mask_timing_normalization 180-320ms — timing envelope для masking
#   * server_hello_delay_min_ms = 20 (только min, без max — иначе Telegram-клиент дропает)
#   * mask_host = "127.0.0.1" явно (без него работает через dns_overrides, но явно надёжнее)
#   * [censorship.tls_fetch] profiles только (доп. параметры grease_enabled/strict_route ломали handshake)
#   * use_middle_proxy = true (use_middle_proxy=false ломал Telegram-клиент)
#   * NO mask_shape_above_cap_blur=true (флаг ломал MTProto reply-flight)
#   * NO tls_new_session_tickets (клиент не ждёт дополнительных tickets)
generate_telemt_toml() {
    local secret="$1"
    local port="${2:-443}"
    local mask_mode="${3:-lite}"   # lite | pro
    local mask_domain="${4:-google.com}"
    local mask_port="${5:-443}"
    local output="${6:-$TELEMT_CONFIG}"

    mkdir -p "$(dirname "$output")"

    # DNS override для pro: домен резолвится в 127.0.0.1
    # чтобы mask-трафик шёл на локальный nginx, а не в интернет
    local dns_line=""
    if [ "$mask_mode" = "pro" ]; then
        dns_line="dns_overrides = [\"${mask_domain}:${mask_port}:127.0.0.1\"]"
    fi

    # ── Fixed mask values (no per-installation jitter) ─────────────────────
    # We tried random per-installation jitter on bucket_floor/timing earlier,
    # but found a fail mode on 2026-06-09: random bucket_floor=1024 +
    # timing_normalization 225..350ms broke real Telegram clients while
    # mtproto-tunnel handshake still passed. With fixed 512/4096 + 180..320ms
    # the issue does not reproduce. Same values as the reference working
    # config on 203.0.113.10 (example.com).
    local bucket_floor=512
    local bucket_cap=4096
    local timing_floor=180
    local timing_ceiling=320

    # tls_emulation: true для lite (нет реального mask_host), false для pro (есть nginx)
    local tls_emul
    if [ "$mask_mode" = "pro" ]; then
        tls_emul="false"
    else
        tls_emul="true"
    fi

    # public_host: в pro mode — реальный домен, в lite — IP сервера (потом пересоберём ссылки)
    local public_host_line=""
    if [ "$mask_mode" = "pro" ]; then
        public_host_line="public_host = \"${mask_domain}\""
    fi

    # ── Preset overrides («режим подбора», lib/diagnose.sh) ───────────────
    # По умолчанию — проверенный рабочий профиль .42 (client_mss=92=MSS92/x16, sh_delay=20).
    # Если в config.json задан preset_id и движок diagnose.sh загружен — берём
    # client_mss / timing / buckets / sh_delay / (опц.) tls_emulation из пресета.
    # Единый источник правды: и свежий install, и миграция зовут эту функцию.
    local client_mss="92"
    local client_mss_bulk="1400"
    local sh_delay=20
    local tls_profiles='["modern_firefox_like", "compat_tls12"]'
    local reanim_synlimit_block="" reanim_timeouts_block="" reanim_tg_connect=""
    local _pid
    _pid=$(config_get preset_id 2>/dev/null || echo "")
    if [ -n "$_pid" ] && type preset_params >/dev/null 2>&1; then
        local _pp _mss _cc _tf _tc _bf _bc _shd _tlsov _profile _synlimit _timeouts
        _pp=$(preset_params "$_pid" 2>/dev/null) || _pp=""
        if [ -n "$_pp" ]; then
            read -r _mss _cc _tf _tc _bf _bc _shd _tlsov _profile _synlimit _timeouts <<< "$_pp"
            [ "$_mss" = "off" ] && _mss=""
            client_mss="$_mss"
            timing_floor="$_tf"; timing_ceiling="$_tc"
            bucket_floor="$_bf"; bucket_cap="$_bc"; sh_delay="$_shd"
            [ "$_tlsov" = "true" ] && tls_emul="true"
            [ "$_tlsov" = "false" ] && tls_emul="false"
            case "$_profile" in
                chrome)        tls_profiles='["modern_chrome_like", "compat_tls12"]' ;;
                firefox-only)  tls_profiles='["modern_firefox_like"]' ;;
                chrome-only)   tls_profiles='["modern_chrome_like"]' ;;
                legacy)        tls_profiles='["legacy_minimal", "compat_tls12"]' ;;
            esac
            # ── Реаниматор (стабильность под DPI). Идея и параметры:
            #    MTproxy-reanimation (c) @LiafanX — github.com/Liafanx/MTproxy-reanimation
            #    У нас сделано НАТИВНО в ядре telemt: synlimit (= тот же per-IP nft SYN-лимит)
            #    + [timeouts]. Без внешних nft-скриптов и watchdog.
            if [ "$_synlimit" = "on" ]; then
                local _slh=1 _slb=1   # жёсткий = рекомендация автора (rate 1/s, burst 1)
                case "$(config_get reanim_synlimit 2>/dev/null || echo hard)" in
                    mid)  _slh=1; _slb=3 ;;
                    soft) _slh=2; _slb=5 ;;
                esac
                reanim_synlimit_block=$(printf '\n# SYN-лимит на IP (нативно в telemt). (c) MTproxy-reanimation @LiafanX\n[[server.listeners]]\nip = "0.0.0.0"\nport = %s\nsynlimit = "nftables"\nsynlimit_seconds = 1\nsynlimit_hitcount = %s\nsynlimit_burst = %s\n' "$port" "$_slh" "$_slb")
            fi
            if [ "$_timeouts" = "on" ]; then
                reanim_tg_connect=$'\ntg_connect = 30'
                reanim_timeouts_block=$(printf '\n# Таймауты по рекомендации MTproxy-reanimation (c) @LiafanX\n[timeouts]\nclient_handshake = 90\nclient_keepalive = 120\n')
            fi
            log_dim "Preset #${_pid}: mss='${client_mss}' cc=${_cc} timing=${_tf}..${_tc} buckets=${_bf}/${_bc} shd=${_shd} tls=${_profile:-firefox} synlimit=${_synlimit:-off} timeouts=${_timeouts:-off}"
        fi
    fi
    local client_mss_toml="\"${client_mss}\""
    local client_mss_bulk_line=""
    if [ -n "$client_mss" ]; then
        client_mss_bulk_line="client_mss_bulk = \"${client_mss_bulk}\""
    fi


    # telemt требует bucket_floor>0 при mask_shape_hardening=true (иначе
    # "censorship.mask_shape_bucket_floor_bytes must be > 0" и telemt НЕ стартует).
    # Пресеты «без шейпинга» (mss-off: bucket=0, timing=0) -> отключаем shaping
    # и нормализацию таймингов флагами, а значения держим валидными.
    local mask_hardening="true" timing_enabled="true"
    if [ "${bucket_floor:-0}" -le 0 ] 2>/dev/null; then mask_hardening="false"; bucket_floor=512; bucket_cap=4096; fi
    if [ "${timing_ceiling:-0}" -le 0 ] 2>/dev/null; then timing_enabled="false"; timing_floor=0; timing_ceiling=0; fi

    cat > "$output" << EOTOML
# goTelegram v${GOTELEGRAM_VERSION} — telemt v3 configuration
# Сгенерировано: $(date -Iseconds)
# Режим: ${mask_mode}

[general]
use_middle_proxy = true
log_level = "normal"

# Реаниматор (ME-recovery): авто-восстановление аплинка к Telegram.
# Встроено в ядро telemt (single-endpoint outage mode + async refill). Пишем явно,
# чтобы функция была активна и пережила перегенерацию конфига при обновлении.
# Значения = дефолты ядра (тюнибельно). На 3.4.25 активны.
me_single_endpoint_outage_mode_enabled = true
me_single_endpoint_outage_disable_quarantine = true
me_single_endpoint_outage_backoff_min_ms = 250
me_single_endpoint_outage_backoff_max_ms = 3000
me_route_no_writer_mode = "hybrid_async_persistent"
me_route_inline_recovery_attempts = 3
me_route_inline_recovery_wait_ms = 3000
me_adaptive_floor_recover_grace_secs = 180${reanim_tg_connect}

[general.modes]
classic = false
secure = false
tls = true

[general.links]
show = "*"
${public_host_line}
public_port = ${port}

[server]
port = ${port}
listen_addr_ipv4 = "0.0.0.0"
max_connections = 5000
metrics_listen = "127.0.0.1:9090"
metrics_whitelist = ["127.0.0.1/32", "::1/128"]
client_mss = ${client_mss_toml}
${client_mss_bulk_line}

[server.api]
enabled = true
listen = "127.0.0.1:9091"
whitelist = ["127.0.0.1/32", "::1/128"]
minimal_runtime_enabled = false
minimal_runtime_cache_ttl_ms = 1000

[censorship]
tls_domain = "${mask_domain}"
tls_emulation = ${tls_emul}
mask = true
mask_host = "127.0.0.1"
mask_port = ${mask_port}
unknown_sni_action = "mask"
mask_shape_hardening = ${mask_hardening}
mask_shape_bucket_floor_bytes = ${bucket_floor}
mask_shape_bucket_cap_bytes = ${bucket_cap}
mask_shape_above_cap_blur_max_bytes = 64
mask_timing_normalization_enabled = ${timing_enabled}
mask_timing_normalization_floor_ms = ${timing_floor}
mask_timing_normalization_ceiling_ms = ${timing_ceiling}
server_hello_delay_min_ms = ${sh_delay}

[censorship.tls_fetch]
profiles = ${tls_profiles}
${reanim_synlimit_block}${reanim_timeouts_block}
[access]
user_max_unique_ips_global_each = 13

[access.users]
main = "${secret}"

[network]
${dns_line}
EOTOML

    chmod 600 "$output"
    log_success "Конфиг telemt записан: $output"
    log_dim "Сценарий: $(human_mode_name "$mask_mode"), домен: $mask_domain, внутренний порт: $mask_port"
    log_dim "Masking params: bucket=${bucket_floor}..${bucket_cap}, timing=${timing_floor}..${timing_ceiling}ms"
}

# ── Добавление дополнительного секрета ───────────────────────────────────────
add_secret_to_config() {
    local name="$1"
    local secret="$2"
    local config="${3:-$TELEMT_CONFIG}"

    if [ ! -f "$config" ]; then
        log_error "Конфиг не найден: $config"
        return 1
    fi

    # telemt v3: добавляем ключ в секцию [access.users]
    # Формат: name = "secret" под блоком [access.users]
    if grep -q '\[access\.users\]' "$config"; then
        sed -i "/\[access\.users\]/a ${name} = \"${secret}\"" "$config"
    else
        cat >> "$config" << EOSECRET

[access.users]
${name} = "${secret}"
EOSECRET
    fi

    log_success "Добавлен секрет: $name"
}

# ── Чтение текущего конфига (telemt v3 формат) ──────────────────────────────
get_config_value() {
    local key="$1"
    local config="${2:-$TELEMT_CONFIG}"

    if [ ! -f "$config" ]; then return 1; fi

    case "$key" in
        secret)
            # [access.users] main = "..."
            awk '
                /^\[access\.users\]/ { in_users=1; next }
                /^\[/ && in_users { exit }
                in_users && /^[[:space:]]*[^#[:space:]][^=]*=/ {
                    user_key=$1
                    gsub(/"/, "", user_key)
                    if (user_key != "main") next

                    value=$0
                    sub(/^[^=]*=[[:space:]]*/, "", value)
                    sub(/^"/, "", value)
                    sub(/".*$/, "", value)
                    gsub(/[[:space:]]/, "", value)
                    if (value != "") {
                        print value
                        found=1
                    }
                    exit
                }
                END { exit found ? 0 : 1 }
            ' "$config"
            ;;
        port)
            # [server] port = 443
            awk '
                /^\[server\]/ { in_server=1; next }
                /^\[/ && in_server { exit }
                in_server && $1 == "port" {
                    sub(/^[^=]*=[[:space:]]*/, "")
                    gsub(/[[:space:]]/, "")
                    print
                    exit
                }
            ' "$config"
            ;;
        mask_host|tls_domain)
            # [censorship] tls_domain = "..."
            awk '
                /^\[censorship\]/ { in_cens=1; next }
                /^\[/ && in_cens { exit }
                in_cens && $1 == "tls_domain" {
                    sub(/^[^=]*=[[:space:]]*"/, "")
                    sub(/".*$/, "")
                    print
                    exit
                }
            ' "$config"
            ;;
        mask_port)
            awk '
                /^\[censorship\]/ { in_cens=1; next }
                /^\[/ && in_cens { exit }
                in_cens && $1 == "mask_port" {
                    sub(/^[^=]*=[[:space:]]*/, "")
                    gsub(/[[:space:]]/, "")
                    print
                    exit
                }
            ' "$config"
            ;;
        *)
            grep "$key" "$config" | head -1 | sed 's/^[^=]*=[[:space:]]*//; s/^"//; s/"$//' | tr -d ' '
            ;;
    esac
}

get_telemt_users_block() {
    local config="${1:-$TELEMT_CONFIG}"
    [ -f "$config" ] || return 1
    awk '
        /^\[access\.users\]/ { in_users=1; next }
        /^\[/ && in_users { exit }
        in_users && /^[[:space:]]*[^#[:space:]][^=]*=/ { print }
    ' "$config"
}

first_telemt_user_secret() {
    local config="${1:-$TELEMT_CONFIG}"
    get_telemt_users_block "$config" | head -1 | sed 's/^[^=]*=[[:space:]]*//; s/^"//; s/".*$//' | tr -d ' '
}

get_telemt_main_secret() {
    local config="${1:-$TELEMT_CONFIG}"
    get_telemt_users_block "$config" | awk -F= '
        {
            key=$1
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
            if (key ~ /^".*"$/ || key ~ /^\047.*\047$/) {
                key=substr(key, 2, length(key) - 2)
            }
            if (key == "main") {
                value=substr($0, index($0, "=") + 1)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
                if (value ~ /^".*"$/ || value ~ /^\047.*\047$/) {
                    value=substr(value, 2, length(value) - 2)
                }
                print value
                exit
            }
        }
    '
}

telemt_users_block_has_main() {
    local users_block="$1"
    printf '%s\n' "$users_block" | awk -F= '
        /^[[:space:]]*#/ || ! /=/ { next }
        {
            key=$1
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
            if (key ~ /^".*"$/ || key ~ /^\047.*\047$/) {
                key=substr(key, 2, length(key) - 2)
            }
            if (key == "main") {
                found=1
                exit
            }
        }
        END { exit found ? 0 : 1 }
    '
}

replace_telemt_users_block() {
    local users_block="$1"
    local config="${2:-$TELEMT_CONFIG}"
    [ -f "$config" ] || return 1
    [ -n "$users_block" ] || return 0

    local tmp users_file status
    tmp=$(mktemp "$(dirname "$config")/.users-next.XXXXXX") || return 1
    users_file=$(mktemp "$(dirname "$config")/.users-secret.XXXXXX") || {
        rm -f -- "$tmp"
        return 1
    }
    chmod 600 "$tmp" "$users_file"
    printf '%s\n' "$users_block" > "$users_file" || {
        rm -f -- "$tmp" "$users_file"
        return 1
    }
    awk -v users_file="$users_file" '
        BEGIN {
            count=0
            while ((getline line < users_file) > 0) lines[++count]=line
            close(users_file)
        }
        /^\[access\.users\]/ {
            found=1
            print
            for (i = 1; i <= count; i++) {
                if (lines[i] != "") print lines[i]
            }
            in_users=1
            next
        }
        /^\[/ && in_users { in_users=0 }
        in_users { next }
        { print }
        END {
            if (!found) {
                print ""
                print "[access.users]"
                for (i = 1; i <= count; i++) {
                    if (lines[i] != "") print lines[i]
                }
            }
        }
    ' "$config" > "$tmp" && mv "$tmp" "$config"
    status=$?
    rm -f -- "$tmp" "$users_file"
    [ "$status" -eq 0 ] || return "$status"
    chmod 600 "$config"
}

toml_bool_value() {
    local table="$1"
    local key="$2"
    local config="${3:-$TELEMT_CONFIG}"
    awk -v table="$table" -v key="$key" '
        $0 == "[" table "]" { in_table=1; next }
        /^\[/ && in_table { exit }
        in_table && $1 == key {
            sub(/^[^=]*=[[:space:]]*/, "")
            gsub(/[[:space:]]/, "")
            print
            exit
        }
    ' "$config"
}

# ── Валидация конфига ────────────────────────────────────────────────────────
validate_telemt_config() {
    local config="${1:-$TELEMT_CONFIG}"

    if [ ! -f "$config" ]; then
        log_error "Конфиг не найден: $config"
        return 1
    fi

    # Проверяем обязательные поля
    local secret port host
    secret=$(get_config_value secret "$config")
    port=$(get_config_value port "$config")
    host=$(get_config_value mask_host "$config")

    local errors=0

    if [ -z "$secret" ]; then
        log_error "Не задан secret"
        ((errors++))
    elif [ ${#secret} -lt 32 ]; then
        log_warning "Secret слишком короткий (${#secret} символов, рекомендуется 32+)"
    fi

    if [ -z "$port" ]; then
        log_error "Не задан порт (bind_to)"
        ((errors++))
    elif [ "$port" -lt 1 ] || [ "$port" -gt 65535 ] 2>/dev/null; then
        log_error "Порт вне диапазона: $port"
        ((errors++))
    fi

    if [ -z "$host" ]; then
        log_error "Не задан маскировочный хост (censorship.tls_domain)"
        ((errors++))
    fi

    if [ $errors -gt 0 ]; then
        log_error "Найдено ошибок: $errors"
        return 1
    fi

    log_success "Конфиг валиден"
    return 0
}

# ── Выбор домена (интерактивный) ─────────────────────────────────────────────
select_quick_domain() {
    echo "" >&2
    echo -e "  ${BOLD}${WHITE}🌐 Выберите домен для маскировки (Fake TLS):${NC}" >&2
    echo -e "  ${DIM}$(printf '─%.0s' {1..50})${NC}" >&2

    local i=1
    local row=""
    for d in "${QUICK_DOMAINS[@]}"; do
        printf "  ${CYAN}%2d)${NC} %-25s" "$i" "$d" >&2
        if (( i % 2 == 0 )); then
            echo "" >&2
        fi
        ((i++))
    done
    if (( (i-1) % 2 != 0 )); then echo "" >&2; fi

    echo -e "  ${DIM}$(printf '─%.0s' {1..50})${NC}" >&2
    echo -ne "  ${WHITE}Выбор (1-${#QUICK_DOMAINS[@]}):${NC} " >&2
    read -r choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#QUICK_DOMAINS[@]} ]; then
        echo "${QUICK_DOMAINS[$((choice-1))]}"
        return 0
    fi

    log_error "Неверный выбор"
    return 1
}

# ── Выбор порта (интерактивный) ──────────────────────────────────────────────
select_port() {
    echo "" >&2
    echo -e "  ${BOLD}${WHITE}🔌 Выберите порт:${NC}" >&2

    # Проверяем стандартные порты
    local busy_443 busy_8443
    busy_443=$(check_port 443)
    busy_8443=$(check_port 8443)

    local label_443="443 (рекомендуется)"
    local label_8443="8443"
    [ -n "$busy_443" ] && label_443="443 ⚠️  занят"
    [ -n "$busy_8443" ] && label_8443="8443 ⚠️  занят"

    echo -e "  ${CYAN}1)${NC} $label_443" >&2
    echo -e "  ${CYAN}2)${NC} $label_8443" >&2
    echo -e "  ${CYAN}3)${NC} Свой порт" >&2

    if [ -n "$busy_443" ]; then
        echo -e "  ${DIM}  ⚠ Порт 443 занят: $(echo "$busy_443" | head -c 60)${NC}" >&2
    fi

    echo -ne "  ${WHITE}Выбор:${NC} " >&2
    read -r choice

    case "$choice" in
        1) echo "443" ;;
        2) echo "8443" ;;
        3)
            echo -ne "  Введите порт (1-65535): " >&2
            read -r custom_port
            if [[ "$custom_port" =~ ^[0-9]+$ ]] && [ "$custom_port" -ge 1 ] && [ "$custom_port" -le 65535 ]; then
                echo "$custom_port"
            else
                log_error "Неверный порт"
                return 1
            fi
            ;;
        *) echo "443" ;;
    esac
}

# ── Генерация ссылки tg://proxy ──────────────────────────────────────────────
generate_proxy_link() {
    local server="${1:-$(get_server_ip)}"
    local port="${2:-443}"
    local secret="$3"
    local mask_host="${4:-}"

    # Если указан mask_host (fake-TLS), формируем ee-секрет
    if [ -n "$mask_host" ]; then
        local domain_hex
        domain_hex=$(printf '%s' "$mask_host" | xxd -p | tr -d '\n')
        secret="ee${secret}${domain_hex}"
    fi

    echo "tg://proxy?server=${server}&port=${port}&secret=${secret}"
}

# ── Вывод информации о прокси ────────────────────────────────────────────────
show_proxy_info() {
    local config="${1:-$TELEMT_CONFIG}"
    local secret port mask_host ip link status

    secret=$(get_config_value secret "$config")
    port=$(get_config_value port "$config")
    mask_host=$(get_config_value mask_host "$config")
    ip=$(get_server_ip)
    status=$(telemt_status)

    local mode domain
    mode=$(config_get mode 2>/dev/null || echo "lite")
    domain=$(config_get domain 2>/dev/null || echo "")

    # Генерация ссылки: оба режима используют ee-секрет с mask_host
    if [ "$mode" = "pro" ] && [ -n "$domain" ]; then
        link=$(generate_proxy_link "$domain" "$port" "$secret" "$domain")
    else
        link=$(generate_proxy_link "$ip" "$port" "$secret" "$mask_host")
    fi

    local status_icon status_text
    case "$status" in
        running) status_icon="✅"; status_text="Работает" ;;
        stopped) status_icon="⏸️";  status_text="Остановлен" ;;
        *)       status_icon="❌"; status_text="Не установлен" ;;
    esac

    echo ""
    echo -e "  ${BOLD}${WHITE}${status_icon} Статус прокси: ${status_text}${NC}"
    echo -e "  ${DIM}$(printf '─%.0s' {1..50})${NC}"
    echo -e "  ${WHITE}Ядро:${NC}       telemt (Rust)"
    if [ "$mode" = "pro" ] && [ -n "$domain" ]; then
        echo -e "  ${WHITE}Домен:${NC}      ${CYAN}${domain}${NC}"
    else
        echo -e "  ${WHITE}IP:${NC}         ${CYAN}${ip}${NC}"
    fi
    echo -e "  ${WHITE}Порт:${NC}       ${CYAN}${port}${NC}"
    echo -e "  ${WHITE}Сценарий:${NC}   ${CYAN}$(human_mode_name "$mode")${NC}"
    echo -e "  ${WHITE}Маскировка:${NC} ${CYAN}${mask_host}${NC}"
    echo -e "  ${WHITE}Secret:${NC}     ${CYAN}${secret:0:16}...${NC}"
    echo -e "  ${DIM}$(printf '─%.0s' {1..50})${NC}"
    echo -e "  ${WHITE}Ссылка:${NC}"
    echo -e "  ${GREEN}${link}${NC}"
    echo ""

    # QR если доступен
    if command -v qrencode &>/dev/null; then
        qrencode -t UTF8 -m 2 "$link" 2>/dev/null
    fi
}

# ── Вывод информации о прокси со своим доменом ───────────────────────────────
# В этом сценарии ссылка содержит домен (не IP) и fake-TLS секрет (ee...)
show_proxy_info_pro() {
    local domain="$1"
    local faketls_secret="$2"
    local public_port="${3:-443}"
    local internal_port="${4:-8443}"

    local link="tg://proxy?server=${domain}&port=${public_port}&secret=${faketls_secret}"

    echo ""
    echo -e "  ${BOLD}${WHITE}✅ Прокси со своим доменом и сайтом настроен${NC}"
    echo -e "  ${DIM}$(printf '─%.0s' {1..55})${NC}"
    echo -e "  ${WHITE}Ядро:${NC}       telemt (Rust)"
    echo -e "  ${WHITE}Домен:${NC}      ${CYAN}${domain}${NC}"
    echo -e "  ${WHITE}Порт:${NC}       ${CYAN}${public_port}${NC} (внешний, telemt)"
    echo -e "  ${WHITE}Схема:${NC}      ${MAGENTA}Свой домен и сайт${NC}"
    echo -e "  ${WHITE}nginx:${NC}      ${CYAN}127.0.0.1:${internal_port}${NC} (внутренний)"
    echo -e "  ${WHITE}Secret:${NC}     ${CYAN}${faketls_secret:0:20}...${NC}"
    echo -e "  ${DIM}$(printf '─%.0s' {1..55})${NC}"
    echo -e "  ${WHITE}Ссылка для Telegram:${NC}"
    echo -e "  ${GREEN}${link}${NC}"
    echo ""
    echo -e "  ${DIM}Провайдер видит: HTTPS-трафик к ${domain}:${public_port}${NC}"
    echo -e "  ${DIM}Telegram-клиент маскирует соединение под TLS${NC}"
    echo ""

    # QR если доступен
    if command -v qrencode &>/dev/null; then
        qrencode -t UTF8 -m 2 "$link" 2>/dev/null
    fi
}
