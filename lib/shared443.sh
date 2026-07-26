#!/bin/bash
# goTelegram Pro v2.5.0 — shared TCP/443 dispatcher helpers

SHARED443_CONFIG="${SHARED443_CONFIG:-/opt/gotelegram/shared-443.json}"
SHARED443_STREAM_CONF="${SHARED443_STREAM_CONF:-/etc/nginx/stream-conf.d/gotelegram-shared443.conf}"
SHARED443_TELEMT_PORT="${SHARED443_TELEMT_PORT:-7443}"
SHARED443_PUBLIC_PORT="${SHARED443_PUBLIC_PORT:-443}"

SHARED443_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
type log_error >/dev/null 2>&1 || source "$SHARED443_LIB_DIR/common.sh"
type install_nginx >/dev/null 2>&1 || source "$SHARED443_LIB_DIR/website.sh"

shared443_detect_nginx_stream() {
    nginx -V 2>&1 | grep -Eq -- '--with-stream|ngx_stream_module|ngx_stream_ssl_preread_module'
}

shared443_install_stream_module() {
    if shared443_detect_nginx_stream; then
        return 0
    fi

    case "$(get_pkg_manager 2>/dev/null || echo unknown)" in
        apt)
            apt_update >/dev/null 2>&1 || true
            apt_install libnginx-mod-stream || return 1
            ;;
        dnf|yum)
            install_pkg nginx-mod-stream || true
            ;;
    esac

    shared443_detect_nginx_stream
}

shared443_ensure_nginx_include() {
    mkdir -p /etc/nginx/stream-conf.d
    if nginx -T 2>/dev/null | grep -q '/etc/nginx/stream-conf.d/\*.conf'; then
        return 0
    fi
    if grep -Eq '^[[:space:]]*stream[[:space:]]*\{' /etc/nginx/nginx.conf 2>/dev/null; then
        log_warning "В nginx уже есть stream-блок, но нет include /etc/nginx/stream-conf.d/*.conf"
        log_dim "Добавьте include вручную или перенесите $SHARED443_STREAM_CONF в существующий stream-блок."
        return 1
    fi

    cp /etc/nginx/nginx.conf "/etc/nginx/nginx.conf.gotelegram.$(date +%Y%m%d_%H%M%S).bak" 2>/dev/null || true
    cat >> /etc/nginx/nginx.conf <<'EOF'

# goTelegram Pro shared TCP/443 routes
stream {
    include /etc/nginx/stream-conf.d/*.conf;
}
EOF
}

shared443_rewrite_telemt_bind() {
    local listen_port="${1:-$SHARED443_TELEMT_PORT}"
    local public_port="${2:-$SHARED443_PUBLIC_PORT}"
    local listen_addr="${3:-127.0.0.1}"

    command -v python3 >/dev/null 2>&1 || {
        log_error "python3 нужен для безопасного изменения $TELEMT_CONFIG"
        return 1
    }

    python3 - "$TELEMT_CONFIG" "$listen_port" "$public_port" "$listen_addr" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
listen_port = sys.argv[2]
public_port = sys.argv[3]
listen_addr = sys.argv[4]
lines = path.read_text(encoding="utf-8", errors="ignore").splitlines() if path.exists() else []
out = []
section = ""
server_seen = False
server_port_seen = False
server_addr_seen = False
links_seen = False
public_seen = False

def flush_section(next_line=None):
    global section, server_port_seen, server_addr_seen, public_seen
    if section == "server":
        if not server_port_seen:
            out.append(f"port = {listen_port}")
        if not server_addr_seen:
            out.append(f'listen_addr_ipv4 = "{listen_addr}"')
    if section == "general.links" and not public_seen:
        out.append(f"public_port = {public_port}")
    if next_line is not None:
        out.append(next_line)

for raw in lines:
    stripped = raw.strip()
    if stripped.startswith("[") and stripped.endswith("]"):
        flush_section(raw)
        section = stripped.strip("[]")
        if section == "server":
            server_seen = True
            server_port_seen = False
            server_addr_seen = False
        elif section == "general.links":
            links_seen = True
            public_seen = False
        continue

    if section == "server" and stripped.startswith("port") and "=" in stripped:
        out.append(f"port = {listen_port}")
        server_port_seen = True
        continue
    if section == "server" and stripped.startswith("listen_addr_ipv4") and "=" in stripped:
        out.append(f'listen_addr_ipv4 = "{listen_addr}"')
        server_addr_seen = True
        continue
    if section == "general.links" and stripped.startswith("public_port") and "=" in stripped:
        out.append(f"public_port = {public_port}")
        public_seen = True
        continue
    out.append(raw)

flush_section()
if not links_seen:
    if out and out[-1].strip():
        out.append("")
    out.extend(["[general.links]", f"public_port = {public_port}"])
if not server_seen:
    if out and out[-1].strip():
        out.append("")
    out.extend(["[server]", f"port = {listen_port}", f'listen_addr_ipv4 = "{listen_addr}"'])

tmp = path.with_suffix(path.suffix + ".tmp")
tmp.write_text("\n".join(out).rstrip() + "\n", encoding="utf-8")
tmp.chmod(0o600)
tmp.replace(path)
PY
}

shared443_write_stream_config() {
    local domain="$1"
    local xray_domain="${2:-}"
    local xray_target="${3:-}"
    local telemt_target="${4:-127.0.0.1:${SHARED443_TELEMT_PORT}}"

    mkdir -p "$(dirname "$SHARED443_STREAM_CONF")"
    {
        echo "# goTelegram Pro shared TCP/443 dispatcher"
        echo "# Browser/Telegram for goTelegram domain goes to telemt; telemt masks the site to nginx."
        echo "map \$ssl_preread_server_name \$gotelegram_shared443_backend {"
        echo "    hostnames;"
        if [[ -n "$xray_domain" && -n "$xray_target" ]]; then
            echo "    ${xray_domain} ${xray_target};"
        fi
        echo "    default ${telemt_target};"
        echo "}"
        echo ""
        echo "server {"
        echo "    listen 0.0.0.0:${SHARED443_PUBLIC_PORT};"
        echo "    proxy_pass \$gotelegram_shared443_backend;"
        echo "    ssl_preread on;"
        echo "    proxy_connect_timeout 5s;"
        echo "    proxy_timeout 10m;"
        echo "}"
    } > "$SHARED443_STREAM_CONF"

    mkdir -p "$(dirname "$SHARED443_CONFIG")"
    if command -v jq >/dev/null 2>&1; then
        jq -n \
            --arg domain "$domain" \
            --arg telemt "$telemt_target" \
            --arg xdomain "$xray_domain" \
            --arg xtarget "$xray_target" \
            --arg updated "$(date -Iseconds)" \
            --argjson public_port "$SHARED443_PUBLIC_PORT" \
            '{
                enabled: true,
                dispatcher: "nginx-stream",
                public_port: $public_port,
                domain: $domain,
                telemt_target: $telemt,
                site_target: "127.0.0.1:8443",
                xray_routes: (if ($xdomain != "" and $xtarget != "") then [{public: ($xdomain + ":443"), target: $xtarget}] else [] end),
                updated_at: $updated
            }' > "$SHARED443_CONFIG"
    else
        cat > "$SHARED443_CONFIG" <<EOF
{"enabled":true,"dispatcher":"nginx-stream","public_port":${SHARED443_PUBLIC_PORT},"domain":"${domain}","telemt_target":"${telemt_target}","site_target":"127.0.0.1:8443","xray_routes":[],"updated_at":"$(date -Iseconds)"}
EOF
    fi
    chmod 600 "$SHARED443_CONFIG" 2>/dev/null || true
}

shared443_enable() {
    local domain="$1"
    local xray_domain="${2:-}"
    local xray_target="${3:-}"
    local telemt_target="127.0.0.1:${SHARED443_TELEMT_PORT}"

    [[ -n "$domain" ]] || domain="$(config_get domain 2>/dev/null || echo "")"
    [[ -n "$domain" ]] || {
        log_error "Не указан домен goTelegram Pro для shared-443"
        return 1
    }

    install_nginx || return 1
    shared443_install_stream_module || {
        log_error "nginx stream/ssl_preread недоступен"
        return 1
    }
    shared443_ensure_nginx_include || return 1

    shared443_rewrite_telemt_bind "$SHARED443_TELEMT_PORT" "$SHARED443_PUBLIC_PORT" "127.0.0.1" || return 1
    systemctl restart "$TELEMT_SERVICE" 2>/dev/null || true

    shared443_write_stream_config "$domain" "$xray_domain" "$xray_target" "$telemt_target"
    if nginx -t 2>/dev/null; then
        systemctl restart nginx
        log_success "shared-443 включён: 0.0.0.0:${SHARED443_PUBLIC_PORT} -> nginx stream -> telemt ${telemt_target}"
        if [[ -n "$xray_domain" && -n "$xray_target" ]]; then
            log_success "Xray route: ${xray_domain}:443 -> ${xray_target}"
        fi
    else
        log_error "nginx -t не прошёл после настройки shared-443"
        nginx -t
        return 1
    fi
}

shared443_detect_direct_conflict() {
    ss -ltnp 2>/dev/null | grep -E '(:|])443[[:space:]]' | grep -Eiv '(nginx|telemt)' || true
}

shared443_status() {
    echo "shared-443 config: $SHARED443_CONFIG"
    [ -f "$SHARED443_CONFIG" ] && cat "$SHARED443_CONFIG" || echo "not enabled"
    local conflict
    conflict="$(shared443_detect_direct_conflict)"
    if [[ -n "$conflict" ]]; then
        echo ""
        echo "direct 443 listeners that need migration behind dispatcher:"
        echo "$conflict"
    fi
}

export -f shared443_detect_nginx_stream shared443_install_stream_module shared443_ensure_nginx_include
export -f shared443_rewrite_telemt_bind shared443_write_stream_config shared443_enable
export -f shared443_detect_direct_conflict shared443_status
