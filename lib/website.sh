#!/bin/bash
# GoTelegram v2.5.0 — Управление сайтом (nginx + certbot + шаблоны)

# ── Установка nginx ──────────────────────────────────────────────────────────
install_nginx() {
    if command -v nginx &>/dev/null; then
        log_dim "nginx уже установлен"
        return 0
    fi
    log_info "Установка nginx..."
    case "$(get_pkg_manager)" in
        apt) apt_update && apt_install nginx || return 1 ;;
        dnf) dnf install -y -q nginx || return 1 ;;
        yum) yum install -y -q nginx || return 1 ;;
    esac
    systemctl enable nginx 2>/dev/null
}

# ── Установка certbot ────────────────────────────────────────────────────────
install_certbot() {
    if command -v certbot &>/dev/null; then
        log_dim "certbot уже установлен"
        return 0
    fi
    log_info "Установка certbot..."
    case "$(get_pkg_manager)" in
        apt) apt_install certbot python3-certbot-nginx || return 1 ;;
        dnf) dnf install -y -q certbot python3-certbot-nginx || return 1 ;;
        yum) yum install -y -q certbot python3-certbot-nginx || return 1 ;;
    esac
}

# ── Активация nginx-конфига с учётом layout дистрибутива ────────────────────
activate_nginx_site() {
    mkdir -p "$(dirname "$NGINX_SITE_CONF")" "$(dirname "$NGINX_SITE_LINK")"
    if [ "$NGINX_SITE_CONF" != "$NGINX_SITE_LINK" ]; then
        ln -sfn "$NGINX_SITE_CONF" "$NGINX_SITE_LINK"
    fi
}

# ── Генерация nginx конфига ──────────────────────────────────────────────────
generate_nginx_config() {
    local domain="$1"
    local proxy_port="${2:-443}"
    local use_ssl="${3:-true}"
    local cert_live_dir="${4:-/etc/letsencrypt/live/$domain}"
    local enable_http_listener="${5:-1}"
    local cert_name="${cert_live_dir##*/}"
    validate_domain "$domain" || {
        log_error "Некорректный домен для nginx: $domain"
        return 1
    }
    case "$cert_live_dir" in
        /etc/letsencrypt/live/*) ;;
        *)
            log_error "Небезопасный путь к сертификату: $cert_live_dir"
            return 1
            ;;
    esac
    [[ "$cert_name" =~ ^[A-Za-z0-9._-]+$ ]] || {
        log_error "Некорректное имя линии сертификата: $cert_name"
        return 1
    }
    [ -s "$cert_live_dir/fullchain.pem" ] && [ -s "$cert_live_dir/privkey.pem" ] || {
        log_error "В выбранной линии Let's Encrypt нет полного сертификата и ключа."
        return 1
    }

    mkdir -p "$(dirname "$NGINX_SITE_CONF")"

    cat > "$NGINX_SITE_CONF" << 'EONGINX'
# GoTelegram v2.5.0 — nginx config
# Pro: nginx на 127.0.0.1:8443 (внутренний), telemt на 0.0.0.0:443 (внешний)
# Обычный браузер → :443 → telemt → 127.0.0.1:8443 → nginx (сайт)

HTTP_SERVER_PLACEHOLDER

server {
    listen 127.0.0.1:SSL_PORT_PLACEHOLDER ssl http2;
    server_name DOMAIN_PLACEHOLDER;

    # SSL сертификаты
    ssl_certificate CERT_DIR_PLACEHOLDER/fullchain.pem;
    ssl_certificate_key CERT_DIR_PLACEHOLDER/privkey.pem;

    # Современные TLS настройки
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    # OCSP stapling
    ssl_stapling on;
    ssl_stapling_verify on;

    # Security headers
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Корень сайта
    root /var/www/gotelegram-site;
    index index.html;

HUB_LOCATION_PLACEHOLDER

    location / {
        try_files $uri $uri/ =404;
        expires 30d;
    }

    # Кеширование статики
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # Скрываем служебные файлы
    location ~ /\. { deny all; }
    location = /robots.txt { allow all; log_not_found off; access_log off; }
    location = /favicon.ico { log_not_found off; access_log off; }
}
EONGINX

    local http_server="" hub_location=""
    local hub_limits_conf="/etc/nginx/conf.d/igproxy-hub-limits.conf"
    if [ "$enable_http_listener" = "1" ]; then
        http_server='server {
    listen 80;
    listen [::]:80;
    server_name DOMAIN_PLACEHOLDER;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
        allow all;
    }

    location / {
        return 301 https://$server_name$request_uri;
    }
}'
    fi
    case "${DEPLOYMENT_ROLE:-standalone}" in
        hub|controller)
            mkdir -p "$(dirname "$hub_limits_conf")"
            cat > "$hub_limits_conf" << 'EOHUBLIMITS'
# IGProxy Hub public API abuse protection.
limit_req_zone $binary_remote_addr zone=igproxy_hub_rate:10m rate=5r/s;
limit_conn_zone $binary_remote_addr zone=igproxy_hub_conn:10m;
EOHUBLIMITS
            hub_location='    # API регистрации узлов; сам процесс слушает только loopback.
    location /__igproxy/ {
        limit_req zone=igproxy_hub_rate burst=10 nodelay;
        limit_conn igproxy_hub_conn 10;
        proxy_pass http://127.0.0.1:1990/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-Proto https;
        proxy_connect_timeout 5s;
        proxy_read_timeout 15s;
        client_body_timeout 10s;
        client_max_body_size 64k;
        limit_except GET POST { deny all; }
    }'
            ;;
        *)
            if [ -f "$hub_limits_conf" ] &&
               grep -q '^# IGProxy Hub public API abuse protection\.$' "$hub_limits_conf"; then
                rm -f -- "$hub_limits_conf"
            fi
            ;;
    esac
    awk -v http="$http_server" -v replacement="$hub_location" '
        $0 == "HTTP_SERVER_PLACEHOLDER" { print http; next }
        $0 == "HUB_LOCATION_PLACEHOLDER" { print replacement; next }
        { print }
    ' "$NGINX_SITE_CONF" > "${NGINX_SITE_CONF}.tmp" &&
        mv "${NGINX_SITE_CONF}.tmp" "$NGINX_SITE_CONF"

    # Домен уже прошёл validate_domain, а имя линии сертификата ограничено
    # безопасным набором символов; разделитель | в значениях невозможен.
    sed -i "s|DOMAIN_PLACEHOLDER|${domain}|g" "$NGINX_SITE_CONF"
    sed -i "s|SSL_PORT_PLACEHOLDER|${proxy_port}|g" "$NGINX_SITE_CONF"
    sed -i "s|CERT_DIR_PLACEHOLDER|${cert_live_dir}|g" "$NGINX_SITE_CONF"

    # Активируем отдельный virtual host, не трогая уже существующие сайты.
    activate_nginx_site

    log_success "nginx конфиг создан для $domain"
}

# ── Временный конфиг (до получения SSL) ──────────────────────────────────────
generate_nginx_temp_config() {
    local domain="$1"

    mkdir -p "$(dirname "$NGINX_SITE_CONF")"
    cat > "$NGINX_SITE_CONF" << EONGINX_TEMP
# GoTelegram — временный конфиг (до получения SSL)
server {
    listen 80;
    listen [::]:80;
    server_name ${domain};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
        allow all;
    }

    root /var/www/gotelegram-site;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EONGINX_TEMP

    activate_nginx_site
    mkdir -p /var/www/certbot
}

# ── Получение SSL сертификата ────────────────────────────────────────────────
_ssl_certificate_live_dir() {
    local domain="$1" require_fresh="${2:-1}" exact candidate cert
    validate_domain "$domain" || return 1
    exact="/etc/letsencrypt/live/$domain"
    for candidate in "$exact" /etc/letsencrypt/live/*; do
        [ -d "$candidate" ] || continue
        cert="$candidate/fullchain.pem"
        [ -s "$cert" ] && [ -s "$candidate/privkey.pem" ] || continue
        openssl x509 -in "$cert" -noout -checkhost "$domain" >/dev/null 2>&1 || continue
        if [ "$require_fresh" = "1" ]; then
            openssl x509 -in "$cert" -noout -checkend 86400 >/dev/null 2>&1 || continue
        fi
        printf '%s\n' "$candidate"
        return 0
    done
    return 1
}

ssl_certificate_live_dir() {
    _ssl_certificate_live_dir "$1" 1
}

ssl_certificate_matching_live_dir() {
    _ssl_certificate_live_dir "$1" 0
}

ssl_certificate_is_usable() {
    ssl_certificate_live_dir "$1" >/dev/null
}

igproxy_certificate_lineage_name() {
    local domain="$1" digest
    validate_domain "$domain" || return 1
    digest=$(printf '%s' "$domain" | sha256sum | awk '{print substr($1,1,16)}')
    [[ "$digest" =~ ^[a-f0-9]{16}$ ]] || return 1
    printf 'igproxy-%s\n' "$digest"
}

obtain_ssl_certificate() {
    local domain="$1"
    local email="${2:-}"
    local cert_live_dir="" dedicated_name="" dedicated_dir=""
    IGPROXY_CERT_WAS_REUSED=0

    if ! cert_live_dir=$(ssl_certificate_live_dir "$domain"); then
        log_info "Получение SSL сертификата для $domain..."

        # Временный конфиг для ACME challenge
        generate_nginx_temp_config "$domain" || return 1
        if ! nginx -t 2>/dev/null; then
            log_error "Временный nginx-конфиг не прошёл проверку; действующий nginx не перезапущен."
            return 1
        fi
        systemctl restart nginx 2>/dev/null || {
            log_error "Не удалось применить временный nginx-конфиг."
            return 1
        }

        local certbot_args=(
            certonly
            --webroot
            -w /var/www/certbot
            -d "$domain"
            --non-interactive
            --agree-tos
        )

        if [ -n "$email" ]; then
            certbot_args+=(--email "$email")
        else
            certbot_args+=(--register-unsafely-without-email)
        fi
        dedicated_name=$(igproxy_certificate_lineage_name "$domain") || return 1
        dedicated_dir="/etc/letsencrypt/live/$dedicated_name"
        certbot_args+=(--cert-name "$dedicated_name")
        if [ -d "$dedicated_dir" ]; then
            certbot_args+=(--force-renewal)
            log_dim "Обновляю отдельную линию IGProxy: $dedicated_name"
        else
            log_dim "Выпускаю отдельную линию IGProxy: $dedicated_name"
        fi

        local certbot_log
        certbot_log=$(mktemp /tmp/gotelegram-certbot.XXXXXX) || return 1
        chmod 600 "$certbot_log"
        if certbot "${certbot_args[@]}" >"$certbot_log" 2>&1; then
            rm -f -- "$certbot_log"
            cert_live_dir=$(ssl_certificate_live_dir "$domain" 2>/dev/null || true)
            if [ -n "$cert_live_dir" ]; then
                log_success "SSL сертификат готов: $cert_live_dir"
                IGPROXY_CERT_WAS_REUSED=0
                return 0
            fi
            log_error "Certbot завершился успешно, но подходящий сертификат для $domain не найден."
            return 1
        else
            log_error "Не удалось получить SSL сертификат"
            tail -n 8 "$certbot_log" | sed 's/^/    /' >&2
            rm -f -- "$certbot_log"
            log_dim "Убедитесь что домен $domain направлен на IP этого сервера"
            log_dim "и порт 80 открыт в файрволе."
            return 1
        fi
    else
        IGPROXY_CERT_WAS_REUSED=1
        log_success "Использую готовый сертификат: $cert_live_dir"
        return 0
    fi
}

# ── Авто-обновление сертификата ──────────────────────────────────────────────
setup_ssl_auto_renewal() {
    # Certbot systemd timer (предпочтительно)
    if [ -f /etc/systemd/system/certbot.timer ] || [ -f /lib/systemd/system/certbot.timer ]; then
        systemctl enable certbot.timer 2>/dev/null
        systemctl start certbot.timer 2>/dev/null
        log_success "Авто-обновление SSL через systemd timer"
        return 0
    fi

    # Изолированный fallback вместо изменения общего root crontab.
    cat > /etc/systemd/system/gotelegram-certbot-renew.service << 'EOSVC'
[Unit]
Description=goTelegram certificate renewal
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/certbot renew --quiet --post-hook "systemctl reload nginx"
EOSVC
    cat > /etc/systemd/system/gotelegram-certbot-renew.timer << 'EOTIMER'
[Unit]
Description=goTelegram certificate renewal timer

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true
RandomizedDelaySec=30m

[Install]
WantedBy=timers.target
EOTIMER
    systemctl daemon-reload >/dev/null 2>&1 || return 1
    systemctl enable --now gotelegram-certbot-renew.timer >/dev/null 2>&1 || return 1
    log_success "Автообновление SSL через отдельный systemd timer"
}

# ── Обновление сертификата вручную ───────────────────────────────────────────
renew_ssl_certificate() {
    log_info "Обновление SSL сертификата..."
    if certbot renew --quiet --post-hook "systemctl reload nginx" 2>/dev/null; then
        log_success "Сертификат обновлён"
        return 0
    else
        log_error "Ошибка обновления сертификата"
        return 1
    fi
}

# ── Дата истечения SSL ───────────────────────────────────────────────────────
get_ssl_expiry() {
    local domain="$1"
    local cert_live_dir cert=""
    cert_live_dir=$(ssl_certificate_matching_live_dir "$domain" 2>/dev/null || true)
    [ -n "$cert_live_dir" ] && cert="$cert_live_dir/fullchain.pem"
    if [ -n "$cert" ] && [ -f "$cert" ]; then
        openssl x509 -enddate -noout -in "$cert" 2>/dev/null | sed 's/notAfter=//'
    else
        echo "N/A"
    fi
}

# ── Деплой шаблона сайта ─────────────────────────────────────────────────────
deploy_template_to_nginx() {
    local template_dir="$1"
    local template_id="${2:-}"
    local source_url="" website_parent stage_dir old_site=""

    if [ ! -d "$template_dir" ] || [ ! -f "$template_dir/index.html" ]; then
        log_error "Шаблон не содержит index.html: $template_dir"
        return 1
    fi
    if [ -n "$(find "$template_dir" -type l -print -quit 2>/dev/null)" ] ||
       [ -n "$(find "$template_dir" ! -type f ! -type d -print -quit 2>/dev/null)" ]; then
        log_error "Шаблон содержит ссылки или специальные файлы и не будет опубликован."
        return 1
    fi
    local template_size_mb template_file_count
    template_size_mb=$(du -sm "$template_dir" 2>/dev/null | awk '{print $1}')
    template_file_count=$(find "$template_dir" -type f 2>/dev/null | wc -l)
    if [ "${template_size_mb:-101}" -gt 100 ] || [ "${template_file_count:-10001}" -gt 10000 ]; then
        log_error "Шаблон превышает лимит 100 MB или 10 000 файлов."
        return 1
    fi
    [ -z "$template_id" ] && template_id=$(basename "$template_dir")
    [ -f "$template_dir/.custom_git_source" ] && source_url=$(head -1 "$template_dir/.custom_git_source" 2>/dev/null || echo "")

    website_parent=$(dirname "$WEBSITE_ROOT")
    mkdir -p "$website_parent"
    stage_dir=$(mktemp -d "$website_parent/.gotelegram-site.XXXXXX") || return 1
    if ! cp -a "$template_dir/." "$stage_dir/"; then
        rm -rf -- "$stage_dir"
        return 1
    fi
    rm -f "$stage_dir/.custom_git_source" 2>/dev/null || true
    echo "$template_id" > "$stage_dir/.gotelegram_template_id" 2>/dev/null || true
    [ -n "$source_url" ] && echo "$source_url" > "$stage_dir/.gotelegram_template_source" 2>/dev/null || true
    chown -R www-data:www-data "$stage_dir" 2>/dev/null || chown -R nginx:nginx "$stage_dir" 2>/dev/null || true
    chmod -R 755 "$stage_dir"

    # Бекапим старый сайт
    if [ -d "$WEBSITE_ROOT" ] && [ "$(ls -A "$WEBSITE_ROOT" 2>/dev/null)" ]; then
        local site_backup_root="/var/lib/gotelegram/site-backups" site_backup_dir
        mkdir -p -m 700 "$site_backup_root"
        site_backup_dir=$(mktemp -d "$site_backup_root/site.XXXXXX") || {
            rm -rf -- "$stage_dir"
            return 1
        }
        old_site="$site_backup_dir/site"
        mv -- "$WEBSITE_ROOT" "$old_site" || {
            rm -rf -- "$stage_dir"
            return 1
        }
        log_dim "Старый сайт сохранён в $site_backup_dir/site"
    elif [ -d "$WEBSITE_ROOT" ]; then
        rmdir -- "$WEBSITE_ROOT" 2>/dev/null || {
            rm -rf -- "$stage_dir"
            return 1
        }
    fi

    if ! mv -- "$stage_dir" "$WEBSITE_ROOT"; then
        [ -n "$old_site" ] && [ -d "$old_site" ] && mv -- "$old_site" "$WEBSITE_ROOT" 2>/dev/null || true
        rm -rf -- "$stage_dir"
        return 1
    fi

    log_success "Шаблон развёрнут в $WEBSITE_ROOT"
}

# ── Полная установка сценария со своим доменом и сайтом ─────────────────────
setup_pro_mode() {
    local domain="$1"
    local template_dir="$2"
    local proxy_port="${3:-443}"
    local email="${4:-}"
    local public_port="${5:-443}"
    local enable_http_listener="${6:-1}"
    local cert_live_dir=""

    log_step "Настройка своего домена и сайта"

    # 1. Устанавливаем nginx
    run_with_spinner "Установка nginx" install_nginx || return 1

    # 2. Устанавливаем certbot
    run_with_spinner "Установка certbot" install_certbot || return 1

    # 3. Деплоим шаблон сайта
    deploy_template_to_nginx "$template_dir" || return 1

    # 4. Получаем SSL
    obtain_ssl_certificate "$domain" "$email" || return 1
    cert_live_dir=$(ssl_certificate_live_dir "$domain") || {
        log_error "После проверки не найден пригодный сертификат для $domain."
        return 1
    }

    # 5. Генерируем полный nginx конфиг с SSL
    generate_nginx_config "$domain" "$proxy_port" true "$cert_live_dir" "$enable_http_listener" || return 1

    # 6. Тестируем и перезапускаем nginx
    if nginx -t 2>/dev/null; then
        systemctl restart nginx
        log_success "nginx запущен с SSL"
    else
        log_error "Ошибка в конфигурации nginx"
        nginx -t
        return 1
    fi

    # 7. Настраиваем авто-обновление SSL
    if [ "${IGPROXY_CERT_WAS_REUSED:-0}" = "1" ] && [ "$enable_http_listener" != "1" ]; then
        log_dim "Существующий сертификат и его механизм продления оставлены без изменений."
    else
        setup_ssl_auto_renewal
    fi

    # 8. Показываем благодарности авторам шаблонов
    show_credits

    log_success "Сайт настроен: $(format_https_url "$domain" "$public_port")"
    return 0
}

# ── Управление nginx ────────────────────────────────────────────────────────
nginx_status() {
    if systemctl is-active --quiet nginx 2>/dev/null; then
        echo "running"
    else
        echo "stopped"
    fi
}

restart_nginx() {
    if nginx -t 2>/dev/null; then
        systemctl restart nginx 2>/dev/null
        log_success "nginx перезапущен"
    else
        log_error "Ошибка конфигурации nginx"
        nginx -t
        return 1
    fi
}

# ── Удаление собственного сайта ──────────────────────────────────────────────
remove_pro_mode() {
    log_info "Удаление сайта и его конфигурации..."
    rm -f "$NGINX_SITE_CONF" "$NGINX_SITE_LINK"
    rm -rf "$WEBSITE_ROOT"
    systemctl restart nginx 2>/dev/null
    log_success "Сайт и его конфигурация удалены (nginx оставлен)"
}

# ── Смена шаблона ────────────────────────────────────────────────────────────
switch_template() {
    local new_template_dir="$1"
    deploy_template_to_nginx "$new_template_dir" "$(basename "$new_template_dir")"
    # nginx не требует перезапуска — статика обновилась на месте
    log_success "Шаблон сайта обновлён"
}
