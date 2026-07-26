#!/bin/bash
# GoTelegram Pro — Bootstrap installer for private repo
# Downloads all files and launches install.sh

set -euo pipefail

REPO="anten-ka/gotelegram_pro"
BRANCH="${GOTELEGRAM_BRANCH:-main}"
PAT="${GOTELEGRAM_PAT:-}"
INSTALL_DIR="/opt/gotelegram"
# Use raw.githubusercontent.com (CDN) — faster and avoids Contents API caching
# issues that occasionally return 404 for recently added files on non-default branches.
RAW="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'
BOLD='\033[1m'

echo ""
echo -e "  ${YELLOW}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "  ${YELLOW}║${NC}  ${BOLD}GoTelegram Pro — Установка${NC}                          ${YELLOW}║${NC}"
echo -e "  ${YELLOW}║${NC}                                                      ${YELLOW}║${NC}"
echo -e "  ${YELLOW}║${NC}  MTProxy менеджер с Telegram-ботом                   ${YELLOW}║${NC}"
echo -e "  ${YELLOW}║${NC}  Stealth-режим, 1800+ шаблонов сайтов                ${YELLOW}║${NC}"
echo -e "  ${YELLOW}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# Check root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "  ${RED}✗${NC} Запустите от root: ${CYAN}sudo bash bootstrap.sh${NC}"
    exit 1
fi

if [ -z "$PAT" ]; then
    echo -e "  ${RED}✗${NC} Не задан GitHub token."
    echo -e "  ${YELLOW}Запустите так:${NC} ${CYAN}GOTELEGRAM_PAT=YOUR_PAT sudo -E bash bootstrap.sh${NC}"
    exit 1
fi

# Check dependencies
for cmd in curl jq; do
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "  ${CYAN}↻${NC} Установка $cmd..."
        apt-get update -qq && apt-get install -y -qq "$cmd" >/dev/null 2>&1
    fi
done

download_file() {
    local remote_path="$1"
    local local_path="$2"
    local dir
    dir=$(dirname "$local_path")
    mkdir -p "$dir"

    # Retry up to 3 times with short backoff to tolerate transient CDN hiccups
    local attempt http_code
    for attempt in 1 2 3; do
        http_code=$(curl -sL -w "%{http_code}" -o "$local_path" \
            -H "Authorization: token ${PAT}" \
            "${RAW}/${remote_path}")
        if [ "$http_code" = "200" ]; then
            return 0
        fi
        sleep 1
    done

    echo -e "  ${RED}✗${NC} Ошибка загрузки ${remote_path} (HTTP ${http_code})"
    return 1
}

# File list
FILES=(
    "install.sh"
    "install_gotelegram_bot.sh"
    "templates_catalog.json"
    "lib/common.sh"
    "lib/telemt.sh"
    "lib/telemt_config.sh"
    "lib/backup.sh"
    "lib/website.sh"
    "lib/templates_catalog.sh"
    "lib/stats.sh"
    "lib/diagnose.sh"
    "lib/i18n.sh"
    "lib/lang/en.sh"
    "lib/lang/ru.sh"
    "gotelegram-bot/bot.py"
    "gotelegram-bot/i18n.py"
    "gotelegram-bot/lang/en.json"
    "gotelegram-bot/lang/ru.json"
    "gotelegram-bot/config.example.env"
    "gotelegram-bot/requirements.txt"
    "gotelegram-bot/README.md"
    "admin-web/server.py"
    "admin-web/static/index.html"
    "admin-web/static/styles.css"
    "admin-web/static/app.js"
)

echo -e "  ${CYAN}↻${NC} Загрузка файлов в ${INSTALL_DIR}..."
mkdir -p "${INSTALL_DIR}/lib/lang" "${INSTALL_DIR}/gotelegram-bot/lang" "${INSTALL_DIR}/admin-web/static"

failed=0
for f in "${FILES[@]}"; do
    if download_file "$f" "${INSTALL_DIR}/${f}"; then
        echo -e "  ${GREEN}✓${NC} ${f}"
    else
        failed=$((failed + 1))
    fi
done

if [ "$failed" -gt 0 ]; then
    echo ""
    echo -e "  ${RED}✗${NC} Не удалось загрузить ${failed} файл(ов)"
    echo -e "  ${YELLOW}Проверьте токен доступа и подключение к сети${NC}"
    exit 1
fi

# Fix permissions and line endings
echo -e "  ${CYAN}↻${NC} Настройка прав..."
chmod +x "${INSTALL_DIR}/install.sh" "${INSTALL_DIR}/install_gotelegram_bot.sh"
chmod +x "${INSTALL_DIR}"/lib/*.sh
chmod +x "${INSTALL_DIR}/admin-web/server.py" 2>/dev/null || true
sed -i 's/\r$//' "${INSTALL_DIR}/install.sh" "${INSTALL_DIR}/install_gotelegram_bot.sh" "${INSTALL_DIR}"/lib/*.sh "${INSTALL_DIR}"/lib/lang/*.sh 2>/dev/null || true
sed -i 's/\r$//' "${INSTALL_DIR}"/gotelegram-bot/*.py "${INSTALL_DIR}"/gotelegram-bot/lang/*.json 2>/dev/null || true
sed -i 's/\r$//' "${INSTALL_DIR}"/admin-web/*.py "${INSTALL_DIR}"/admin-web/static/* 2>/dev/null || true

# Create symlink
ln -sf "${INSTALL_DIR}/install.sh" /usr/local/bin/gotelegram
echo -e "  ${GREEN}✓${NC} Команда ${CYAN}gotelegram${NC} доступна"

echo ""
echo -e "  ${GREEN}✓${NC} Установка завершена! Запуск..."
echo ""

# Launch
# curl|bash кладёт ЭТОТ скрипт в stdin; перецепляем stdin дочернего install.sh на
# управляющий терминал (если он есть), чтобы промпты читали ввод. Detached-запуск
# (нет /dev/tty) сохраняет пайп — для автоматизации.
if [ ! -t 0 ] && { true < /dev/tty; } 2>/dev/null; then
    exec bash "${INSTALL_DIR}/install.sh" "$@" < /dev/tty
else
    exec bash "${INSTALL_DIR}/install.sh" "$@"
fi
