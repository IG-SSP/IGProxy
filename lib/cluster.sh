#!/bin/bash
# IGProxy Hub / Node orchestration helpers.

IGPROXY_HUB_DIR="${IGPROXY_HUB_DIR:-/opt/igproxy-hub}"
IGPROXY_HUB_SERVICE="${IGPROXY_HUB_SERVICE:-igproxy-hub}"
IGPROXY_HUB_PORT="${IGPROXY_HUB_PORT:-1990}"
IGPROXY_NODE_DIR="${IGPROXY_NODE_DIR:-/opt/igproxy-node}"
IGPROXY_NODE_STATE_DIR="${IGPROXY_NODE_STATE_DIR:-/var/lib/igproxy-node}"
IGPROXY_NODE_SERVICE="${IGPROXY_NODE_SERVICE:-igproxy-node}"

cluster_valid_role() {
    case "${1:-}" in
        hub|node|controller|standalone) return 0 ;;
        *) return 1 ;;
    esac
}

cluster_current_role() {
    local role="${DEPLOYMENT_ROLE:-}"
    if [ -z "$role" ] && [ -f "$GOTELEGRAM_CONFIG" ] && command -v jq >/dev/null 2>&1; then
        role=$(jq -r '.deployment_role // empty' "$GOTELEGRAM_CONFIG" 2>/dev/null || true)
    fi
    cluster_valid_role "$role" || role="standalone"
    printf '%s\n' "$role"
}

cluster_persist_role() {
    local role="$1" tmp lock_file
    cluster_valid_role "$role" || return 1
    DEPLOYMENT_ROLE="$role"
    export DEPLOYMENT_ROLE
    [ -f "$GOTELEGRAM_CONFIG" ] || return 0
    tmp=$(mktemp "$(dirname "$GOTELEGRAM_CONFIG")/.role-next.XXXXXX") || return 1
    lock_file="${GOTELEGRAM_CONFIG_LOCK:-/run/gotelegram/config.lock}"
    mkdir -p "$(dirname "$lock_file")" || { rm -f -- "$tmp"; return 1; }
    exec 9>"$lock_file" || { rm -f -- "$tmp"; return 1; }
    flock 9 || { exec 9>&-; rm -f -- "$tmp"; return 1; }
    if jq --arg role "$role" '.deployment_role = $role' "$GOTELEGRAM_CONFIG" > "$tmp" &&
       chmod 600 "$tmp" &&
       mv "$tmp" "$GOTELEGRAM_CONFIG"; then
        exec 9>&-
        rm -f -- "$tmp"
        return 0
    fi
    exec 9>&-
    rm -f -- "$tmp"
    return 1
}

cluster_public_hub_url() {
    local mode domain port
    mode=$(config_get mode 2>/dev/null || true)
    domain=$(config_get domain 2>/dev/null || true)
    port=$(config_get port 2>/dev/null || echo 443)
    if [ "$mode" = "pro" ] && [ -n "$domain" ]; then
        printf '%s/__igproxy\n' "$(format_https_url "$domain" "$port")"
    fi
}

cluster_install_hub_service() {
    local source="$SCRIPT_DIR/cluster/hub_server.py" python_bin
    [ -f "$source" ] || {
        log_error "Не найден компонент центра: $source"
        return 1
    }
    python_bin=$(command -v python3) || {
        log_error "Для центра управления требуется python3."
        return 1
    }
    "$python_bin" -c 'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' "$source" || {
        log_error "Компонент центра не прошёл проверку Python."
        return 1
    }
    install -d -m 700 "$IGPROXY_HUB_DIR"
    install -m 700 "$source" "$IGPROXY_HUB_DIR/hub_server.py"
    cat > "/etc/systemd/system/${IGPROXY_HUB_SERVICE}.service" << EOF
[Unit]
Description=IGProxy Hub node registry
After=network.target

[Service]
Type=simple
WorkingDirectory=$IGPROXY_HUB_DIR
ExecStart=$python_bin $IGPROXY_HUB_DIR/hub_server.py
Restart=always
RestartSec=5
RuntimeDirectory=gotelegram
RuntimeDirectoryMode=0750
RuntimeDirectoryPreserve=yes
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/gotelegram /run/gotelegram
ReadOnlyPaths=-/opt/gotelegram/current -/opt/gotelegram/releases $IGPROXY_HUB_DIR
InaccessiblePaths=-/opt/gotelegram/backups
CapabilityBoundingSet=
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
ProtectClock=true
ProtectHostname=true
ProtectProc=invisible
ProcSubset=pid
PrivateDevices=true
RestrictNamespaces=true
RestrictRealtime=true
LockPersonality=true
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
Environment=IGPROXY_HUB_HOST=127.0.0.1
Environment=IGPROXY_HUB_PORT=$IGPROXY_HUB_PORT

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now "$IGPROXY_HUB_SERVICE" >/dev/null 2>&1
    if ! systemctl is-active --quiet "$IGPROXY_HUB_SERVICE"; then
        log_error "Служба центра управления не запустилась."
        return 1
    fi
    # systemd переводит процесс в active раньше, чем Python успевает открыть
    # loopback-сокет. Даём Hub до 10 секунд на готовность вместо ложного отката.
    local waited=0 hub_ready=0
    while [ "$waited" -lt 10 ]; do
        if curl -fsS --max-time 2 \
            "http://127.0.0.1:${IGPROXY_HUB_PORT}/v1/health" >/dev/null 2>&1; then
            hub_ready=1
            break
        fi
        systemctl is-active --quiet "$IGPROXY_HUB_SERVICE" || break
        sleep 1
        waited=$((waited + 1))
    done
    if [ "$hub_ready" != "1" ]; then
        log_error "Локальная проверка IGProxy Hub не пройдена."
        return 1
    fi
    log_success "Центр управления работает на 127.0.0.1:${IGPROXY_HUB_PORT}"
}

cluster_create_pairing_code() {
    local raw
    raw=$(python3 "$IGPROXY_HUB_DIR/hub_server.py" create-code --ttl 1800) || return 1
    printf '%s' "$raw" | jq -r '.code'
}

cluster_show_pairing_code() {
    local code hub_url
    code=$(cluster_create_pairing_code) || {
        log_error "Не удалось создать одноразовый код подключения."
        return 1
    }
    hub_url=$(cluster_public_hub_url)
    echo ""
    if type ig_ui_heading >/dev/null 2>&1; then
        ig_ui_heading "ПОДКЛЮЧЕНИЕ УЗЛОВ" "Одноразовый код готов" \
            "Он действует 30 минут и срабатывает только один раз."
        [ -n "$hub_url" ] && ig_ui_key_value "Адрес центра" "$hub_url"
        ig_ui_key_value "Код подключения" "$code"
        ig_ui_note "На дополнительном VPS выберите роль «Прокси-узел» и вставьте эти данные."
    else
        echo "  Адрес центра: ${hub_url:-настройте HTTPS reverse proxy к 127.0.0.1:${IGPROXY_HUB_PORT}}"
        echo "  Код подключения: $code"
        echo "  Код действует 30 минут и используется один раз."
    fi
}

cluster_prompt_line() {
    local prompt="$1" default="${2:-}" value
    echo -ne "  ${WHITE:-}${prompt}${NC:-}" >&2
    [ -n "$default" ] && echo -ne " [${default}]" >&2
    echo -ne ": " >&2
    IFS= read -r value
    printf '%s\n' "${value:-$default}"
}

cluster_prompt_secret() {
    local prompt="$1" value
    echo -ne "  ${WHITE:-}${prompt}:${NC:-} " >&2
    IFS= read -r -s value
    echo "" >&2
    printf '%s\n' "$value"
}

cluster_install_node_service() {
    local hub_url="$1" label="$2" pairing_code="$3"
    local source="$SCRIPT_DIR/cluster/node_agent.py" python_bin public_ip config_tmp code_file
    [ -f "$source" ] || {
        log_error "Не найден агент узла: $source"
        return 1
    }
    python_bin=$(command -v python3) || {
        log_error "Для агента узла требуется python3."
        return 1
    }
    "$python_bin" -c 'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' "$source" || {
        log_error "Агент узла не прошёл проверку Python."
        return 1
    }
    case "$hub_url" in
        https://*) ;;
        *)
            log_error "Адрес центра должен начинаться с https://"
            return 1
            ;;
    esac
    hub_url="${hub_url%/}"
    label=$(printf '%s' "$label" | tr '\r\n\t' '   ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//' | cut -c1-48)
    [ -n "$label" ] || {
        log_error "Название узла не может быть пустым."
        return 1
    }
    [ -n "$pairing_code" ] || {
        log_error "Не указан одноразовый код подключения."
        return 1
    }
    public_ip=$(get_server_ip 2>/dev/null || true)
    install -d -m 700 "$IGPROXY_NODE_DIR" "$IGPROXY_NODE_STATE_DIR"
    install -m 700 "$source" "$IGPROXY_NODE_DIR/node_agent.py"
    config_tmp=$(mktemp "$IGPROXY_NODE_STATE_DIR/.node-next.XXXXXX") || return 1
    code_file=$(mktemp "$IGPROXY_NODE_STATE_DIR/.pairing-code.XXXXXX") || {
        rm -f -- "$config_tmp"
        return 1
    }
    printf '%s' "$pairing_code" > "$code_file"
    chmod 600 "$config_tmp" "$code_file"
    jq -n \
        --arg hub_url "$hub_url" \
        --arg label "$label" \
        --rawfile pairing_code "$code_file" \
        --arg public_ip "$public_ip" \
        '{
            schema: 1,
            hub_url: $hub_url,
            label: $label,
            pairing_code: $pairing_code,
            public_ip: $public_ip
        }' > "$config_tmp" || {
            rm -f -- "$config_tmp" "$code_file"
            return 1
        }
    install -m 600 "$config_tmp" "$IGPROXY_NODE_STATE_DIR/node.json" || {
        rm -f -- "$config_tmp" "$code_file"
        return 1
    }
    rm -f -- "$config_tmp" "$code_file"
    cat > "/etc/systemd/system/${IGPROXY_NODE_SERVICE}.service" << EOF
[Unit]
Description=IGProxy Node outbound agent
After=network-online.target telemt.service
Wants=network-online.target
Requires=telemt.service

[Service]
Type=simple
WorkingDirectory=$IGPROXY_NODE_STATE_DIR
ExecStart=$python_bin $IGPROXY_NODE_DIR/node_agent.py
Restart=always
RestartSec=10
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadOnlyPaths=/opt/gotelegram /etc/telemt
ReadOnlyPaths=$IGPROXY_NODE_DIR
ReadWritePaths=$IGPROXY_NODE_STATE_DIR
CapabilityBoundingSet=
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
ProtectClock=true
ProtectHostname=true
ProtectProc=invisible
ProcSubset=pid
PrivateDevices=true
RestrictNamespaces=true
RestrictRealtime=true
LockPersonality=true
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
Environment=IGPROXY_NODE_CONFIG=$IGPROXY_NODE_STATE_DIR/node.json

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now "$IGPROXY_NODE_SERVICE" >/dev/null 2>&1
    local waited=0
    while [ "$waited" -lt 30 ]; do
        if jq -e '.node_token and (.node_token | length > 20)' \
            "$IGPROXY_NODE_STATE_DIR/node.json" >/dev/null 2>&1; then
            log_success "Узел зарегистрирован в едином центре."
            log_dim "Регистрация выполнена исходящим HTTPS-запросом; входящий служебный порт не открывался."
            return 0
        fi
        systemctl is-active --quiet "$IGPROXY_NODE_SERVICE" || break
        sleep 2
        waited=$((waited + 2))
    done
    log_error "Агент установлен, но центр не подтвердил регистрацию."
    journalctl -u "$IGPROXY_NODE_SERVICE" -n 8 --no-pager 2>/dev/null || true
    return 1
}

cluster_configure_node_interactive() {
    local hub_url label pairing_code default_label
    default_label=$(hostname 2>/dev/null || echo "Новый сервер")
    if type ig_ui_heading >/dev/null 2>&1; then
        ig_ui_heading "ШАГ 4 · ЕДИНАЯ СЕТЬ" "Подключение к центру" \
            "Возьмите адрес и одноразовый код в основном IGProxy."
    fi
    hub_url=$(cluster_prompt_line "HTTPS-адрес центра" "")
    label=$(cluster_prompt_line "Название кнопки сервера" "$default_label")
    pairing_code=$(cluster_prompt_secret "Одноразовый код")
    cluster_install_node_service "$hub_url" "$label" "$pairing_code"
}

cluster_finalize_deployment_role() {
    local role="$1" hub_url had_hub=0
    cluster_persist_role "$role" || return 1
    case "$role" in
        hub|controller)
            [ -f "$GOTELEGRAM_DIR/hub-registry.json" ] && had_hub=1
            cluster_install_hub_service || return 1
            hub_url=$(cluster_public_hub_url)
            if [ -z "$hub_url" ]; then
                log_warning "Центр пока доступен только локально."
                log_dim "Для подключения внешних узлов нужен HTTPS reverse proxy /__igproxy/ -> 127.0.0.1:${IGPROXY_HUB_PORT}/"
            fi
            if [ "$had_hub" = "0" ]; then
                cluster_show_pairing_code
            else
                log_success "Связь с существующими узлами сохранена."
                log_dim "Новый код можно создать: gotelegram → Управление → Сеть серверов."
            fi
            ;;
        node)
            if [ ! -f "$IGPROXY_NODE_STATE_DIR/node.json" ] &&
               [ -f "$IGPROXY_NODE_DIR/node.json" ]; then
                install -d -m 700 "$IGPROXY_NODE_STATE_DIR"
                install -m 600 "$IGPROXY_NODE_DIR/node.json" "$IGPROXY_NODE_STATE_DIR/node.json"
            fi
            if jq -e '.node_token and (.node_token | length > 20)' \
                "$IGPROXY_NODE_STATE_DIR/node.json" >/dev/null 2>&1; then
                python3 -c 'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' \
                    "$SCRIPT_DIR/cluster/node_agent.py" || return 1
                install -m 700 "$SCRIPT_DIR/cluster/node_agent.py" "$IGPROXY_NODE_DIR/node_agent.py"
                systemctl restart "$IGPROXY_NODE_SERVICE" &&
                    systemctl is-active --quiet "$IGPROXY_NODE_SERVICE" || {
                        log_error "Обновлённый агент узла не запустился."
                        return 1
                    }
                log_success "Регистрация узла и его токен сохранены."
            else
                cluster_configure_node_interactive
            fi
            ;;
        standalone)
            ;;
    esac
}

cluster_show_nodes() {
    [ -x "$IGPROXY_HUB_DIR/hub_server.py" ] || {
        log_warning "Этот сервер не является центром управления."
        return 1
    }
    python3 "$IGPROXY_HUB_DIR/hub_server.py" list-nodes | jq -r '
        if length == 0 then
            "  Подключённых узлов пока нет."
        else
            .[] |
            "  \(.label) · \(if .online then "онлайн" else "не отвечает" end) · последнее соединение: \(.last_seen)"
        end
    '
}

menu_cluster() {
    local role choice
    role=$(cluster_current_role)
    echo ""
    echo -e "  ${BOLD}${WHITE}Сеть IGProxy${NC}"
    echo -e "  ${DIM}Роль: $(installer_role_title "$role" 2>/dev/null || echo "$role")${NC}"
    case "$role" in
        hub|controller)
            echo -e "  ${CYAN}1${NC}) Показать узлы"
            echo -e "  ${CYAN}2${NC}) Создать код подключения"
            echo -e "  ${CYAN}3${NC}) Перезапустить центр"
            echo -e "  ${CYAN}0${NC}) Назад"
            echo -ne "  ${WHITE}Выбор:${NC} "
            read -r choice
            case "$choice" in
                1) cluster_show_nodes ;;
                2) cluster_show_pairing_code ;;
                3) systemctl restart "$IGPROXY_HUB_SERVICE" ;;
            esac
            ;;
        node)
            echo -e "  Агент: $(systemctl is-active "$IGPROXY_NODE_SERVICE" 2>/dev/null || echo stopped)"
            echo -e "  ${CYAN}1${NC}) Переподключить к центру"
            echo -e "  ${CYAN}2${NC}) Показать последние события"
            echo -e "  ${CYAN}0${NC}) Назад"
            echo -ne "  ${WHITE}Выбор:${NC} "
            read -r choice
            case "$choice" in
                1) cluster_configure_node_interactive ;;
                2) journalctl -u "$IGPROXY_NODE_SERVICE" -n 40 --no-pager ;;
            esac
            ;;
        *)
            echo -e "  ${DIM}Автономный сервер не подключён к единому центру.${NC}"
            echo -e "  ${CYAN}1${NC}) Подключить к центру как дополнительный узел"
            echo -e "  ${CYAN}0${NC}) Назад"
            echo -ne "  ${WHITE}Выбор:${NC} "
            read -r choice
            if [ "$choice" = "1" ]; then
                cluster_configure_node_interactive && cluster_persist_role node
            fi
            ;;
    esac
}
