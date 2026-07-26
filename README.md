# goTelegram Pro

**goTelegram Pro** — установщик и панель управления Telegram MTProxy на базе ядра `telemt`. Проект ставит на VPS прокси, сайт-маскировку, Telegram-бота, локальную web-админку, сбор статистики и бэкапы.

Главная идея: снаружи сервер выглядит как обычный HTTPS-сайт, а Telegram-клиенты используют тот же домен/порт для MTProxy. Управлять можно из SSH-меню, Telegram-бота или локальной web-панели через SSH-туннель.

## Что Входит

- ядро `telemt` с fake-TLS маскировкой;
- CLI-меню `gotelegram`;
- Lite-режим без домена и Pro-режим с доменом/сайтом/Let's Encrypt;
- Telegram-бот для статуса, ссылок, QR, бэкапов, шаблонов, ключей и статистики;
- локальная web-админка на `127.0.0.1:1984`;
- глобальная и per-key история трафика;
- ручные и scheduled бэкапы;
- shared-443 схема для совместной работы с 3x-ui/Xray.

## Установка

Запускать под `root` на Ubuntu/Debian:

```bash
export GOTELEGRAM_PAT="YOUR_READ_ONLY_GITHUB_TOKEN"; bash <(curl -sL -H "Authorization: token $GOTELEGRAM_PAT" https://raw.githubusercontent.com/anten-ka/gotelegram_pro/main/bootstrap.sh)
```

`bootstrap.sh` скачает файлы в `/opt/gotelegram`, создаст `/usr/local/bin/gotelegram` и откроет главное меню.

## Режимы

**Lite** работает сразу без домена. Клиент подключается к `IP:443`, а прокси имитирует TLS под популярный домен вроде `google.com`.

**Pro** требует домен, который указывает на VPS. Telegram-клиенты и обычные браузеры используют один публичный домен на `443`: Telegram-трафик идёт в `telemt`, браузер открывает сайт-маскировку через nginx.

## Web-Админка

Админка слушает только локально на сервере:

```text
127.0.0.1:1984
```

Открой через SSH-туннель:

```bash
ssh -L 1984:127.0.0.1:1984 root@SERVER_IP
```

Потом в браузере:

```text
http://127.0.0.1:1984/
```

Внутри есть dashboard, сервисы, проверка сайта, кто слушает `443`, графики трафика, ключи пользователей, QR, IP-лимиты, бэкапы, логи, переключение языка и светлая/тёмная тема.

## Ветки

- `main` — продакшен и ветка установки по умолчанию.
- `beta` — публичная бета для следующих сборок и пользовательского тестирования.
- `alpha` — ранние личные сборки владельца.

Новые изменения сначала идут в `alpha`, потом после проверки в `beta`, и только затем в `main`.

## Документация

- [DOCS_HUMAN.md](DOCS_HUMAN.md) — человеческое руководство с нуля.
- [DOCS_AI.md](DOCS_AI.md) — подробная техническая карта для ИИ-агентов и разработчиков.
- [gotelegram-bot/README.md](gotelegram-bot/README.md) — заметки по Telegram-боту.

## Проверки Перед Пушем

Перед пушем:

```bash
bash -n bootstrap.sh install.sh lib/*.sh
python3 -m unittest tests.test_admin_features tests.test_bot_features
PYTHONPYCACHEPREFIX=/tmp/gotelegram-pycache python3 -m py_compile gotelegram-bot/bot.py admin-web/server.py
node --check admin-web/static/app.js
git diff --check
```
