#!/bin/bash
# goTelegram — verified, atomic release bootstrap

set -euo pipefail
umask 077

INSTALL_ROOT="${GOTELEGRAM_INSTALL_ROOT:-/opt/gotelegram}"
COMMAND_PATH="${GOTELEGRAM_COMMAND_PATH:-/usr/local/bin/gotelegram}"
RELEASE_URL="${GOTELEGRAM_RELEASE_URL:-}"
RELEASE_SHA256="${GOTELEGRAM_RELEASE_SHA256:-}"
TOKEN_FILE="${GOTELEGRAM_TOKEN_FILE:-}"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

fail() {
    echo -e "  ${RED}✗${NC} $*" >&2
    exit 1
}

show_bootstrap_header() {
    echo ""
    echo -e "  ${CYAN}╭────────────────────────────────────────────────────────────╮${NC}"
    echo -e "  ${CYAN}│${NC}  ${GREEN}◆${NC} ${CYAN}IGProxy${NC}  безопасная установка единой сети прокси         ${CYAN}│${NC}"
    echo -e "  ${CYAN}╰────────────────────────────────────────────────────────────╯${NC}"
    echo ""
}

bootstrap_step() {
    local current="$1" title="$2"
    echo -e "  ${CYAN}◆${NC} ${current}/4  ${title}"
}

cleanup() {
    local path="${WORK_DIR:-}"
    case "$path" in
        /tmp/gotelegram-bootstrap.*) rm -rf -- "$path" ;;
    esac
}
trap cleanup EXIT HUP INT TERM

[ "$(id -u)" -eq 0 ] || fail "Запустите установщик от root."
[ -n "$RELEASE_URL" ] || fail "Не задан GOTELEGRAM_RELEASE_URL."
[[ "$RELEASE_SHA256" =~ ^[a-fA-F0-9]{64}$ ]] || \
    fail "GOTELEGRAM_RELEASE_SHA256 должен содержать 64 символа SHA-256."

for cmd in curl tar sha256sum awk; do
    command -v "$cmd" >/dev/null 2>&1 || fail "Не найдена обязательная команда: $cmd"
done

show_bootstrap_header
WORK_DIR=$(mktemp -d /tmp/gotelegram-bootstrap.XXXXXX)
ARCHIVE="$WORK_DIR/release.tar.gz"
CURL_CONFIG="$WORK_DIR/curl.conf"

{
    echo 'fail'
    echo 'location'
    echo 'silent'
    echo 'show-error'
    echo 'retry = 3'
    echo 'connect-timeout = 15'
    echo 'max-time = 300'
    if [ -n "$TOKEN_FILE" ]; then
        [ -f "$TOKEN_FILE" ] || fail "Не найден файл токена: $TOKEN_FILE"
        [ "$(stat -c '%a' "$TOKEN_FILE" 2>/dev/null)" = "600" ] || \
            fail "Файл токена должен иметь права 600: $TOKEN_FILE"
        IFS= read -r release_token < "$TOKEN_FILE"
        [ -n "$release_token" ] || fail "Файл токена пуст."
        printf 'header = "Authorization: Bearer %s"\n' "$release_token"
        release_token=""
    fi
} > "$CURL_CONFIG"
chmod 600 "$CURL_CONFIG"

bootstrap_step 1 "Загружаю проверенный релиз"
curl --config "$CURL_CONFIG" --output "$ARCHIVE" "$RELEASE_URL"

bootstrap_step 2 "Проверяю SHA-256 и безопасные пути"
actual_sha=$(sha256sum "$ARCHIVE" | awk '{print $1}')
[ "$actual_sha" = "${RELEASE_SHA256,,}" ] || \
    fail "SHA-256 релиза не совпал. Ничего не установлено."

if ! tar tzf "$ARCHIVE" | awk '
    BEGIN { ok=1 }
    /^\// { ok=0 }
    /(^|\/)\.\.(\/|$)/ { ok=0 }
    /\\/ { ok=0 }
    END { exit(ok ? 0 : 1) }
'; then
    fail "Архив содержит небезопасные пути."
fi

PAYLOAD="$WORK_DIR/payload"
mkdir -m 700 "$PAYLOAD"
tar xzf "$ARCHIVE" -C "$PAYLOAD" --no-same-owner --no-same-permissions

for required in RELEASE-MANIFEST.sha256 install.sh lib/common.sh \
    lib/installer_wizard.sh lib/installer_ui.sh lib/cluster.sh lib/backup.sh \
    cluster/hub_server.py cluster/node_agent.py admin-web/server.py; do
    [ -f "$PAYLOAD/$required" ] || fail "В релизе отсутствует $required"
done

if ! (
    cd "$PAYLOAD"
    sha256sum -c RELEASE-MANIFEST.sha256 >/dev/null
); then
    fail "Внутренний манифест релиза не прошёл проверку."
fi

bash -n "$PAYLOAD/install.sh"
for script in "$PAYLOAD"/lib/*.sh; do
    bash -n "$script"
done

bootstrap_step 3 "Активирую релиз атомарно"
release_id="${actual_sha:0:16}"
release_dir="$INSTALL_ROOT/releases/$release_id"
mkdir -p -m 700 "$INSTALL_ROOT/releases"

if [ ! -d "$release_dir" ]; then
    mv -- "$PAYLOAD" "$release_dir"
fi
chmod -R go-w "$release_dir"
chmod +x "$release_dir/install.sh" "$release_dir/install_gotelegram_bot.sh"
chmod +x "$release_dir"/lib/*.sh

next_link="$INSTALL_ROOT/.current-${release_id}"
ln -s "releases/$release_id" "$next_link"
mv -Tf "$next_link" "$INSTALL_ROOT/current"
mkdir -p "$(dirname "$COMMAND_PATH")"
ln -sfn "$INSTALL_ROOT/current/install.sh" "$COMMAND_PATH"

bootstrap_step 4 "Открываю интерактивный мастер"
echo -e "  ${GREEN}✓${NC} Проверенный релиз ${release_id} активирован атомарно."
echo -e "  ${YELLOW}i${NC} Данные и ключи в ${INSTALL_ROOT} не изменялись."
echo ""

if [ "${GOTELEGRAM_BOOTSTRAP_ACTIVATE_ONLY:-0}" = "1" ]; then
    exit 0
fi

if [ ! -t 0 ] && { true < /dev/tty; } 2>/dev/null; then
    exec bash "$INSTALL_ROOT/current/install.sh" "$@" < /dev/tty
else
    exec bash "$INSTALL_ROOT/current/install.sh" "$@"
fi
