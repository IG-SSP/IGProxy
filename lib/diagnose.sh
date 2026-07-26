#!/usr/bin/env bash
# lib/diagnose.sh — «Режим подбора» (anti-DPI preset diagnostics).
#
# Три тира режимов (сверху вниз = от макс. защиты к макс. маскировке формы):
#   🛟 тир1 реаниматор (synlimit + таймауты, рек. @LiafanX) — макс. стабильность под DPI
#   📘 тир2 по докам (synlimit + keepalive ядра)
#   🛡 тир3 наши маск-режимы (MSS-клэмп + шейпинг формы)
# Авто-режим подбирает самый СТАБИЛЬНЫЙ рабочий пресет: сверху вниз до первого рабочего,
# затем уточнение вверх. Ручной — выбор по номеру с описанием.
#
# Главный урок 2.6.3: handshake ломал не конфиг маскировки, а bbr + узкий MSS. Поэтому
# bbr не используется ни в одном пресете — везде cubic.
#
# Источник правды для значений конфига — generate_telemt_toml: он читает preset_id из
# config.json и через preset_params() подставляет параметры. Здесь — лестница, применение
# и измерение. Все функции, вызываемые через $()/read (preset_params, _relayed_octets,
# measure_window), печатают в stdout ТОЛЬКО полезную нагрузку; любой UI/лог — в stderr.

# ── Лестница пресетов ────────────────────────────────────────────────────────
# Поля: id|name|mss|cc|timing_floor|timing_ceil|bucket_floor|bucket_cap|sh_delay|tls_override|desc|profile|synlimit|timeouts
#   synlimit: on|off (нативный SYN-лимит на IP, [[server.listeners]])  ·  timeouts: on|off (tg_connect+[timeouts])
#   Три тира: 🛟 реаниматор(автор) → 📘 доки → 🛡 наши маск-режимы
#   mss: off | <число-строкой: 92=MSS92/x16, 800, 1200…> | 2in8 | extreme-low
#   tls_override: keep (по режиму) | true | false
DIAG_PRESETS=(
  '1|реаним·firefox|off|cubic|20|60|1024|49152|0|keep|отпечаток Firefox — по умолчанию|firefox|on|on'
  '2|реаним·chrome|off|cubic|20|60|1024|49152|0|keep|отпечаток Chrome — если Firefox палится|chrome|on|on'
  '3|реаним·legacy|off|cubic|20|60|1024|49152|0|keep|legacy — старые/строгие сети|legacy|on|on'
  '4|MEKO style|off|bbr|20|60|1024|49152|0|keep|SYN-фильтр + BBR + MSS off (идея @Mekotofeuka)|firefox|on|off'
  '5|docs·firefox|off|cubic|20|60|1024|49152|0|keep|отпечаток Firefox|firefox|on|off'
  '6|docs·chrome|off|cubic|20|60|1024|49152|0|keep|отпечаток Chrome|chrome|on|off'
  '7|mss92 shape++|92|cubic|180|320|512|4096|20|keep|узкий MSS, сильная маскировка, медленнее|firefox|off|off'
  '8|mss92 shape+|92|cubic|80|180|1024|8192|10|keep|узкий MSS, маскировка легче, быстрее|firefox|off|off'
  '9|mss800 shape-|800|cubic|30|90|1024|24576|0|keep|компромисс скорость/маскировка|firefox|off|off'
  '10|🧪 firefox-only|92|cubic|180|320|512|4096|20|keep|🧪 TLS1.3 без compat (как #7)|firefox-only|off|off'
)

DIAG_DEFAULT_PRESET=1          # дефолт = проверенный якорь .42
DIAG_WINDOW="${DIAG_WINDOW:-60}"            # окно измерения, сек
DIAG_WARMUP="${DIAG_WARMUP:-8}"             # пауза после рестарта telemt
DIAG_WARMUP_SECS="${DIAG_WARMUP_SECS:-20}"   # прогрев пула соединений к Telegram после переключения пресета
DIAG_THRESHOLD_MB="${DIAG_THRESHOLD_MB:-10}"  # порог «трафик полетел», МБ
DIAG_COARSE_STEP="${DIAG_COARSE_STEP:-3}"   # крупный шаг при поиске сверху

diag_preset_count() { echo "${#DIAG_PRESETS[@]}"; }

# _diag_row <id> -> строка пресета (или код 1)
_diag_row() { printf '%s\n' "${DIAG_PRESETS[@]}" | awk -F'|' -v i="$1" '$1==i{print;f=1} END{exit !f}'; }

# preset_params <id> — ПЕЧАТАЕТ в stdout: "mss cc tf tc bf bc shd tlsov profile synlimit timeouts" (для generate_telemt_toml).
# Только данные, без UI (вызывается через $()).
preset_params() {
    local row; row="$(_diag_row "$1")" || return 1
    awk -F'|' '{print $3, $4, $5, $6, $7, $8, $9, $10, $12, $13, $14}' <<< "$row"
}

# diagnose_preset_cc — congestion control сохранённого пресета (или cubic). Для apply_network_sysctl.
diagnose_preset_cc() {
    local pid cc
    pid=$(config_get preset_id 2>/dev/null || echo "")
    [ -z "$pid" ] && { echo cubic; return 0; }
    cc=$(_diag_row "$pid" 2>/dev/null | awk -F'|' '{print $4}')
    [ -n "$cc" ] && echo "$cc" || echo cubic
}

# ── Применение CC (sysctl), параметризовано ──────────────────────────────────
# diagnose_set_cc <cc> — выставить congestion control. cubic/reno — глушим bbr в
# /etc/sysctl.conf (он перебивает drop-in). bbr — наоборот, не трогаем и грузим модуль.
diagnose_set_cc() {
    local cc="${1:-cubic}"
    [[ "$cc" =~ ^(cubic|reno|bbr)$ ]] || cc=cubic
    if [ "$cc" != "bbr" ]; then
        if grep -qsE '^[[:space:]]*net\.ipv4\.tcp_congestion_control[[:space:]]*=[[:space:]]*bbr' /etc/sysctl.conf 2>/dev/null; then
            sed -i.gotelegram.bak '/^[[:space:]]*net\.ipv4\.tcp_congestion_control[[:space:]]*=[[:space:]]*bbr/d' /etc/sysctl.conf 2>/dev/null || true
        fi
    fi
    local qdisc="fq_codel"; [ "$cc" = "bbr" ] && qdisc="fq"
    local f="/etc/sysctl.d/99-zz-gotelegram.conf"
    local desired="net.core.rmem_max=4194304
net.core.wmem_max=4194304
net.core.default_qdisc=${qdisc}
net.ipv4.tcp_congestion_control=${cc}"
    if [ ! -f "$f" ] || [ "$(cat "$f" 2>/dev/null)" != "$desired" ]; then
        printf '%s\n' "$desired" > "$f" 2>/dev/null || { log_warning "Не удалось записать $f (sysctl)" >&2; return 0; }
    fi
    modprobe "tcp_${cc}" 2>/dev/null || true
    sysctl --system >/dev/null 2>&1 || true
    sysctl -w "net.ipv4.tcp_congestion_control=${cc}" >/dev/null 2>&1 || true
    log_info "CC: ${cc} + ${qdisc}" >&2
    return 0
}

# ── Применение пресета ───────────────────────────────────────────────────────
# apply_preset <id> — сохранить preset_id, перегенерить конфиг (подхватит пресет),
# выставить CC, перезапустить telemt. Side-effect функция (не через $()); UI в stderr.
apply_preset() {
    local id="$1" row name cc
    row="$(_diag_row "$id")" || { log_error "Пресет '$id' не найден" >&2; return 1; }
    name=$(awk -F'|' '{print $2}' <<< "$row")
    cc=$(awk -F'|' '{print $4}' <<< "$row")
    # ── Благодарности авторам при выборе режима ──
    local _syn _tmo
    _syn=$(awk -F'|' '{print $13}' <<< "$row"); _tmo=$(awk -F'|' '{print $14}' <<< "$row")
    case "$name" in
        *MEKO*) log_info "🙏 Режим «MEKO style» — идея и настройки: github.com/Mekotofeuka/MTPROTO_FIX_By_MEKO (спасибо @Mekotofeuka)" >&2 ;;
        *) if [ "$_syn" = "on" ] && [ "$_tmo" = "on" ]; then
               log_info "🙏 Реаниматор (SYN-лимит + таймауты) — по MTproxy-reanimation: github.com/Liafanx/MTproxy-reanimation (спасибо @LiafanX)" >&2
           elif [ "$_syn" = "on" ]; then
               log_info "🙏 Режим «по докам» MTproxy-reanimation: github.com/Liafanx/MTproxy-reanimation (спасибо @LiafanX)" >&2
           fi ;;
    esac

    local secret port mode domain mask_port
    secret=$(get_config_value secret "$TELEMT_CONFIG" 2>/dev/null || echo "")
    [ -z "$secret" ] && secret=$(config_get secret 2>/dev/null || echo "")
    port=$(config_get port 2>/dev/null || echo 443)
    mode=$(config_get mode 2>/dev/null || echo lite)
    domain=$(config_get domain 2>/dev/null || echo "")
    if [ "$mode" = "pro" ]; then
        [ -z "$domain" ] && domain=$(config_get mask_host 2>/dev/null || echo "")
        mask_port=8443
    else
        domain=$(config_get mask_host 2>/dev/null || echo google.com)
        mask_port=443
    fi
    if [ -z "$secret" ]; then log_error "Нет secret — прокси не настроен?" >&2; return 1; fi

    log_step "Применяю пресет #${id} (${name}), CC=${cc}" >&2
    bot_update_config_field preset_id "$id" || log_warning "preset_id не сохранён в config.json" >&2
    # users_block сохраняем (миграционный инвариант — не теряем доп. ключи)
    local users_block; users_block=$(get_telemt_users_block "$TELEMT_CONFIG" 2>/dev/null || true)
    generate_telemt_toml "$secret" "$port" "$mode" "$domain" "$mask_port" "$TELEMT_CONFIG" >&2
    if [ -n "$users_block" ] && type replace_telemt_users_block >/dev/null 2>&1; then
        replace_telemt_users_block "$users_block" "$TELEMT_CONFIG" >&2 2>/dev/null || true
    fi
    diagnose_set_cc "$cc"
    restart_telemt >&2 || { log_error "telemt не перезапустился на пресете #${id}" >&2; return 1; }
    return 0
}

# ── Измерение трафика ────────────────────────────────────────────────────────
# _list_user_names — имена ключей из [access.users] живого конфига.
_list_user_names() {
    awk '
      /^\[access\.users\]/ {u=1; next}
      /^\[/ && u {exit}
      u && /^[[:space:]]*[^#[:space:]][^=]*=/ { k=$1; gsub(/"/,"",k); if(k!="") print k }
    ' "$TELEMT_CONFIG" 2>/dev/null
}

# _relayed_octets — суммарно прорелеенные байты по всем ключам (telemt API :9091).
# Печатает ТОЛЬКО число. Fallback — iptables-счётчик на dpt:443.
_relayed_octets() {
    local total=0 got=0 u payload val
    if command -v curl >/dev/null 2>&1; then
        while IFS= read -r u; do
            [ -z "$u" ] && continue
            payload=$(curl -sS --max-time 2 "http://127.0.0.1:9091/v1/users/${u}" 2>/dev/null || true)
            val=$(echo "$payload" | jq -r '.data.total_octets // .total_octets // empty' 2>/dev/null)
            if [[ "$val" =~ ^[0-9]+$ ]]; then total=$((total+val)); got=1; fi
        done < <(_list_user_names)
    fi
    if [ "$got" = "1" ]; then echo "$total"; return 0; fi
    # fallback: iptables dpt:443 (если правило стоит, см. stats.sh)
    local ipt
    ipt=$(iptables -nvxL 2>/dev/null | grep 'dpt:443' | grep -v ' lo ' | awk '{s+=$2} END{print s+0}')
    echo "${ipt:-0}"
}

# measure_window <secs> — ждёт начала трафика, мерит дельту байт и таймауты.
# Печатает ОДНУ строку: "bytes timeouts started" (started=1 если трафик пошёл).
measure_window() {
    local secs="${1:-$DIAG_WINDOW}" start now base cur started=0 deadline_wait tmo
    base=$(_relayed_octets); start=$(date +%s)
    # фаза 1: ждём появления трафика (до половины окна)
    deadline_wait=$(( secs / 2 )); [ "$deadline_wait" -lt 10 ] && deadline_wait=10
    log_info "Жду появления трафика (скролль медиа-канал через прокси)…" >&2
    while :; do
        sleep 3; cur=$(_relayed_octets)
        if [ "$cur" -gt "$base" ] 2>/dev/null; then started=1; break; fi
        now=$(date +%s); [ $(( now - start )) -ge "$deadline_wait" ] && break
    done
    if [ "$started" = "0" ]; then
        # трафик не пошёл — не ждём полное окно (быстрый вывод)
        tmo=$(journalctl -u "$TELEMT_SERVICE" --since "-${deadline_wait}s" --no-pager 2>/dev/null | grep -c 'Telegram handshake timeout')
        echo "0 ${tmo:-0} 0"; return 0
    fi
    # фаза 2: домеряем до конца окна
    while :; do now=$(date +%s); [ $(( now - start )) -ge "$secs" ] && break; sleep 2; done
    cur=$(_relayed_octets)
    local bytes=$(( cur - base )); [ "$bytes" -lt 0 ] && bytes=0
    tmo=$(journalctl -u "$TELEMT_SERVICE" --since "-${secs}s" --no-pager 2>/dev/null | grep -c 'Telegram handshake timeout')
    echo "${bytes} ${tmo:-0} ${started}"
}

# ── Авто-режим ───────────────────────────────────────────────────────────────
# Сверху (#1 = тир-1 реаниматор, самый стабильный) вниз крупным шагом до первого
# рабочего, затем уточнение вверх по 1 → выбираем самый стабильный рабочий режим.
diagnose_auto() {
    local thr=$(( DIAG_THRESHOLD_MB * 1024 * 1024 )) n; n=$(diag_preset_count)
    local start_id=1 saved
    saved=$(config_get preset_id 2>/dev/null || echo "")
    local orig="$saved"   # вернём этот конфиг, если подбор прервётся
    # Старт ВСЕГДА с #1: тир-1 (реаниматор) — самый стабильный, проверяем его первым,
    # чтобы автоподбор не «перепрыгивал» лучшие режимы (новый 3-тировый порядок).
    echo "" >&2
    log_step "Авто-подбор режима (окно ${DIAG_WINDOW}с, порог ${DIAG_THRESHOLD_MB} МБ)" >&2
    log_info "Подключи Telegram к прокси и листай канал с медиа всё время теста." >&2

    local id="$start_id" first_ok="" tries=0
    # крупный шаг вниз до первого рабочего
    while [ "$id" -le "$n" ]; do
        if _diag_try "$id" "$thr"; then first_ok="$id"; break; fi
        tries=$(( tries + 1 ))
        # Защита: если на первом пресете нет вообще никакого сигнала (ни байт,
        # ни handshake-таймаутов, трафик не пошёл) — клиент не подключён.
        # Не молотим всю лестницу впустую.
        if [ "$tries" = "1" ] && [ "${_DIAG_STARTED:-0}" = "0" ] && [ "${_DIAG_TMO:-0}" = "0" ] && [ "${_DIAG_BYTES:-0}" = "0" ]; then
            echo "" >&2
            log_warning "Трафик от клиента не обнаружен — прокси установлен, но мерить нечего." >&2
            log_info "Подключи Telegram к прокси, начни листать канал с медиа и запусти подбор позже: меню → Подбор режима → Авто." >&2
            log_info "Возвращаю прежний рабочий режим…" >&2
            apply_preset "${orig:-$DIAG_DEFAULT_PRESET}" >&2 2>/dev/null || true
            return 2
        fi
        id=$(( id + DIAG_COARSE_STEP ))
    done
    if [ -z "$first_ok" ]; then
        log_warning "Рабочий пресет не найден до низа лестницы. Возможно, домен/IP режет DPI — попробуй другой домен." >&2
        apply_preset "${orig:-$DIAG_DEFAULT_PRESET}" >&2 2>/dev/null || true
        return 1
    fi
    # уточнение вверх: ищем более СТАБИЛЬНЫЙ рабочий (выше по списку, ближе к тиру-1)
    local best="$first_ok" probe=$(( first_ok - 1 ))
    while [ "$probe" -ge 1 ] && [ "$probe" -gt $(( first_ok - DIAG_COARSE_STEP )) ]; do
        if _diag_try "$probe" "$thr"; then best="$probe"; probe=$(( probe - 1 )); else break; fi
    done
    apply_preset "$best" >&2
    local name; name=$(_diag_row "$best" | awk -F'|' '{print $2}')
    echo "" >&2
    log_success "Готово. Лучший рабочий режим: #${best} (${name}) — применён и сохранён (вкл. CC ядра)." >&2
    echo "$best"
}

# _diag_try <id> <threshold_bytes> — применить, прогреть, замерить, вердикт. 0=рабочий.
_diag_try() {
    local id="$1" thr="$2" name desc res bytes tmo started
    name=$(_diag_row "$id" | awk -F'|' '{print $2}'); desc=$(_diag_row "$id" | awk -F'|' '{print $11}')
    echo "" >&2
    log_step "Пресет #${id} (${name}) — ${desc}" >&2
    apply_preset "$id" >&2 || return 1
    log_info "Прогрев ${DIAG_WARMUP}с…" >&2; sleep "$DIAG_WARMUP"
    res=$(measure_window "$DIAG_WINDOW"); read -r bytes tmo started <<< "$res"
    _DIAG_BYTES="${bytes:-0}"; _DIAG_TMO="${tmo:-0}"; _DIAG_STARTED="${started:-0}"
    local mb=$(( bytes / 1024 / 1024 ))
    if [ "${tmo:-0}" -le 1 ] && [ "${bytes:-0}" -ge "$thr" ]; then
        log_success "✓ Рабочий: ${mb} МБ за ${DIAG_WINDOW}с, timeouts=${tmo}" >&2; return 0
    fi
    log_warning "✗ Не прошёл: ${mb} МБ, timeouts=${tmo}, трафик_пошёл=${started}" >&2; return 1
}

# ── Ручной режим ─────────────────────────────────────────────────────────────
diagnose_table() {
    local cur; cur=$(config_get preset_id 2>/dev/null || echo "$DIAG_DEFAULT_PRESET")
    echo "" >&2
    echo "  Режимы анти-DPI  ·  текущий: #${cur}" >&2
    echo -e "  ${DIM:-}↑ выше = стабильнее под DPI   ↓ ниже = сильнее маскировка формы${NC:-}" >&2
    local row id name mss cc tf tc bf bc shd tlsov desc profile synlim tmo last="" tier mark
    for row in "${DIAG_PRESETS[@]}"; do
        IFS='|' read -r id name mss cc tf tc bf bc shd tlsov desc profile synlim tmo <<< "$row"
        if [ "$synlim" = "on" ] && [ "$tmo" = "on" ]; then tier=1
        elif [ "$cc" = "bbr" ]; then tier=2
        elif [ "$synlim" = "on" ]; then tier=3; else tier=4; fi
        if [ "$tier" != "$last" ]; then
            last="$tier"; echo "" >&2
            case "$tier" in
              1) echo "  🛟 Реаниматор — макс. стабильность, SYN-лимит + таймауты (идея @LiafanX)" >&2 ;;
              2) echo "  🔧 MEKO style — SYN-фильтр + BBR (идея @Mekotofeuka)" >&2 ;;
              3) echo "  📘 По докам — SYN-лимит + keepalive ядра (по докам @LiafanX)" >&2 ;;
              4) echo "  🛡 Маскировка формы — MSS-клэмп + шейпинг (без SYN-лимита)" >&2 ;;
            esac
        fi
        mark="  "; [ "$id" = "$cur" ] && mark="▸ "
        printf '   %s%-2s %-17s %s\n' "$mark" "$id" "$name" "$desc" >&2
    done
    echo "" >&2
    log_warning "Сверху вниз: SYN-защита слабеет, маскировка формы растёт — подбирай под сеть." >&2
}
_bar() {
    local v="$1" max="$2" k i s=""
    [ -z "$max" ] && max=1; [ "$max" -le 0 ] 2>/dev/null && max=1
    k=$(( v * 5 / max ))
    [ "$k" -lt 0 ] && k=0; [ "$k" -gt 5 ] && k=5
    for ((i=0; i<5; i++)); do if [ "$i" -lt "$k" ]; then s+="▮"; else s+="░"; fi; done
    printf '%s' "$s"
}

diagnose_manual() {
    diagnose_table
    echo "" >&2
    printf '  Номер пресета (Enter — отмена): ' >&2; read -r sel
    [ -z "$sel" ] && { log_info "Отменено." >&2; return 0; }
    _diag_row "$sel" >/dev/null || { log_error "Нет такого пресета." >&2; return 1; }
    apply_preset "$sel" || return 1
    _diag_warmup_wait
    log_success "Пресет #${sel} применён. Проверь подключение в Telegram." >&2
}

# ── Оценки пользователя (1-5) в config.json: preset_ratings{"id":rating} ──
_diag_save_rating() {  # <id> <rating>
    [ -f "$GOTELEGRAM_CONFIG" ] || return 0
    local tmp; tmp=$(mktemp) || return 0
    if jq --arg k "$1" --argjson v "$2" '.preset_ratings = ((.preset_ratings // {}) + {($k): $v})' "$GOTELEGRAM_CONFIG" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$GOTELEGRAM_CONFIG"; chmod 600 "$GOTELEGRAM_CONFIG"
    else rm -f "$tmp"; fi
}
_diag_get_rating() { jq -r --arg k "$1" '.preset_ratings[$k] // empty' "$GOTELEGRAM_CONFIG" 2>/dev/null; }

# ссылка на прокси (одна на все режимы — секрет/домен не меняются)
_diag_proxy_link() {
    local sec dom port hex
    sec=$(get_config_value secret "$TELEMT_CONFIG" 2>/dev/null)
    port=$(config_get port 2>/dev/null || echo 443)
    dom=$(config_get domain 2>/dev/null); [ -z "$dom" ] && dom=$(config_get mask_host 2>/dev/null)
    [ -z "$dom" ] && dom=$(get_server_ip 2>/dev/null)
    hex=$(printf '%s' "$dom" | xxd -p | tr -d '\n')
    printf 'tg://proxy?server=%s&port=%s&secret=ee%s%s' "$dom" "$port" "$sec" "$hex"
}

_diag_input_src() { if [ ! -t 0 ] && [ -r /dev/tty ]; then echo /dev/tty; else echo /dev/stdin; fi; }

# Прогрев после переключения: telemt поднимает пул соединений к Telegram ~10-15с.
# Без этого ожидания пользователь проверяет «в окне прогрева» и думает, что не работает.
_diag_warmup_wait() {
    local w
    echo "" >&2
    echo "  ⏳ Telemt перезапущен — идёт прогрев (поднимает соединения к Telegram)." >&2
    echo "  ВАЖНО: переподключаться и проверять можно ТОЛЬКО после отсчёта," >&2
    echo "  иначе покажется, что режим не работает." >&2
    for w in $(seq "${DIAG_WARMUP_SECS:-15}" -1 1); do
        printf '\r  Прогрев: осталось %2dс ...        ' "$w" >&2
        sleep 1
    done
    printf '\r%*s\r' 42 '' >&2
    echo "  ✅ Прогрев завершён — переподключи Telegram и проверь режим." >&2
    echo "  Если не подключается: УДАЛИ и заново ДОБАВЬ прокси в клиенте (или перезапусти Telegram)." >&2
}

diagnose_rated() {
    local n; n=$(diag_preset_count)
    local orig; orig=$(config_get preset_id 2>/dev/null || echo "")
    local link; link=$(_diag_proxy_link)
    local src; src=$(_diag_input_src)
    echo "" >&2
    log_step "Тест режимов с оценкой (1-5)" >&2
    echo "  Применю каждый режим по очереди. После каждого: переподключи Telegram" >&2
    echo "  к прокси, попробуй (открой канал с медиа, полистай) и оцени:" >&2
    echo "  1 = не работает · 3 = плохо · 5 = отлично." >&2
    echo "" >&2
    echo "  Ссылка (одна на все режимы):" >&2
    echo "  ${link}" >&2
    local id name desc rating ans best_id="" best_rate=0
    for id in $(seq 1 "$n"); do
        name=$(_diag_row "$id" | awk -F'|' '{print $2}'); desc=$(_diag_row "$id" | awk -F'|' '{print $11}')
        echo "" >&2
        log_step "Режим #${id}/${n}: ${name} — ${desc}" >&2
        if ! apply_preset "$id" >&2; then log_warning "Не применился — пропускаю." >&2; continue; fi
        _diag_warmup_wait
        local prev; prev=$(_diag_get_rating "$id"); [ -n "$prev" ] && echo "  (прошлая оценка: ${prev})" >&2
        while :; do
            echo -ne "  Переподключись, проверь и оцени [1-5], 0=пропустить, q=выйти: " >&2
            read -r ans < "$src" || ans=q
            case "$ans" in
                [1-5]) rating="$ans"; break ;;
                0) rating=""; break ;;
                q|Q) log_info "Прервано. Возвращаю прежний режим…" >&2; apply_preset "${orig:-$DIAG_DEFAULT_PRESET}" >&2 2>/dev/null || true; return 0 ;;
                *) log_warning "Введи 1-5, 0 (пропустить) или q (выйти)." >&2 ;;
            esac
        done
        [ -z "$rating" ] && continue
        _diag_save_rating "$id" "$rating"
        if [ "$rating" -gt "$best_rate" ]; then best_rate="$rating"; best_id="$id"; fi
        if [ "$rating" = "5" ]; then
            echo -ne "  Отлично! Остаться на этом режиме [s] или продолжить тест [Enter]: " >&2
            read -r ans < "$src" || ans=""
            case "$ans" in s|S|y|Y|да|Да) log_success "Оставлен режим #${id} (${name}), оценка 5." >&2; return 0 ;; esac
        fi
    done
    # Итог
    echo "" >&2
    diagnose_show_ratings
    echo -ne "  На каком режиме остановиться? номер (Enter — лучший #${best_id:-$DIAG_DEFAULT_PRESET}): " >&2
    read -r ans < "$src" || ans=""
    [ -z "$ans" ] && ans="${best_id:-$DIAG_DEFAULT_PRESET}"
    if _diag_row "$ans" >/dev/null 2>&1; then
        apply_preset "$ans" >&2; name=$(_diag_row "$ans" | awk -F'|' '{print $2}'); local fr; fr=$(_diag_get_rating "$ans")
        log_success "Выбран режим #${ans} (${name}), оценка ${fr:-—}." >&2
    else
        apply_preset "${orig:-$DIAG_DEFAULT_PRESET}" >&2 2>/dev/null || true
    fi
}

diagnose_show_ratings() {
    local id name r cur; cur=$(config_get preset_id 2>/dev/null)
    log_step "Твои оценки режимов:" >&2
    for id in $(seq 1 "$(diag_preset_count)"); do
        name=$(_diag_row "$id" | awk -F'|' '{print $2}'); r=$(_diag_get_rating "$id")
        local mark=""; [ "$id" = "$cur" ] && mark=" ← сейчас"
        printf '  #%-2s %-13s оценка: %-3s%s\n' "$id" "$name" "${r:-—}" "$mark" >&2
    done
    echo "" >&2
}

# ── Подменю ──────────────────────────────────────────────────────────────────
_diag_stability_warning() {
    echo "" >&2
    log_warning "Двигаясь по списку ВНИЗ, вы повышаете скорость, но СНИЖАЕТЕ стабильность." >&2
    log_info "Риск: при переборе режимов сервер может попасть под временную блокировку DPI" >&2
    log_info "(от ~10 минут до неопределённого времени)." >&2
    log_info "Иногда нужно подождать разблокировки, чтобы режим, который работал ранее," >&2
    log_info "снова стал доступен." >&2
}

diagnose_menu() {
    _diag_stability_warning
    while true; do
        local cur; cur=$(config_get preset_id 2>/dev/null || echo "$DIAG_DEFAULT_PRESET (дефолт)")
        echo "" >&2
        echo "  Подбор режима (анти-DPI). Текущий режим: #${cur}" >&2
        echo "  1) Тест режимов с оценкой 1-5 (рекомендуется)" >&2
        echo "  2) Ручной выбор по номеру" >&2
        echo "  3) Таблица режимов" >&2
        echo "  4) Мои оценки" >&2
        echo "  5) 🛟 Реаниматор: настройки SYN-лимита / iOS keepalive + благодарность" >&2
        echo "  0) Назад" >&2
        printf '  > ' >&2; read -r c
        case "$c" in
            1) diagnose_rated ;;
            2) diagnose_manual ;;
            3) diagnose_table ;;
            4) diagnose_show_ratings ;;
            5) diagnose_reanim_menu ;;
            0) break ;;
            *) log_error "Неверный выбор" >&2 ;;
        esac
    done
}

# ── 🛟 Реаниматор: настройки + благодарность автору ──────────────────────────
# iOS keepalive-фикс ядра (по докам MTproxy-reanimation): 60/15/3 вместо 7200/75/9.
diagnose_ios_keepalive() {
    local mode="${1:-on}" f="/etc/sysctl.d/99-zz-gotelegram-keepalive.conf"
    if [ "$mode" = "on" ]; then
        printf 'net.ipv4.tcp_keepalive_time=60\nnet.ipv4.tcp_keepalive_intvl=15\nnet.ipv4.tcp_keepalive_probes=3\n' > "$f" 2>/dev/null \
            || { log_warning "Не удалось записать $f" >&2; return 1; }
        sysctl -p "$f" >/dev/null 2>&1 || sysctl --system >/dev/null 2>&1 || true
        log_success "iOS keepalive-фикс ядра включён (60/15/3)." >&2
    else
        rm -f "$f" 2>/dev/null
        sysctl -w net.ipv4.tcp_keepalive_time=7200 >/dev/null 2>&1 || true
        sysctl -w net.ipv4.tcp_keepalive_intvl=75   >/dev/null 2>&1 || true
        sysctl -w net.ipv4.tcp_keepalive_probes=9   >/dev/null 2>&1 || true
        log_info "iOS keepalive-фикс выключен (дефолты ядра 7200/75/9)." >&2
    fi
}

# Перегенерировать конфиг, если текущий режим использует synlimit (чтобы новая жёсткость применилась).
_diag_reapply_if_reanim() {
    local cur sl; cur=$(config_get preset_id 2>/dev/null)
    [ -z "$cur" ] && return 0
    sl=$(_diag_row "$cur" 2>/dev/null | awk -F'|' '{print $13}')
    if [ "$sl" = "on" ]; then
        log_info "Текущий режим #${cur} использует SYN-лимит — перегенерирую конфиг с новой жёсткостью…" >&2
        apply_preset "$cur" >&2 || true
    fi
}

diagnose_reanim_menu() {
    local src; src=$(_diag_input_src)
    while true; do
        local sl ios; sl=$(config_get reanim_synlimit 2>/dev/null); [ -z "$sl" ] && sl="hard"
        ios=$(config_get reanim_ios_keepalive 2>/dev/null); [ -z "$ios" ] && ios="off"
        echo "" >&2
        echo "  ════════════ 🛟 Реаниматор (стабильность под DPI) ════════════" >&2
        echo "  Основано на MTproxy-reanimation © @LiafanX" >&2
        echo "  https://github.com/Liafanx/MTproxy-reanimation  — спасибо автору!" >&2
        echo "" >&2
        echo "  Идея: ограничить SYN-флуд DPI-сканеров на один IP + поджать таймауты/" >&2
        echo "  keepalive, чтобы прокси не валился. У нас сделано НАТИВНО в ядре telemt" >&2
        echo "  (synlimit + [timeouts]) — без внешних nft-скриптов и watchdog-демона." >&2
        echo "" >&2
        echo "  Жёсткость SYN-лимита сейчас : ${sl}" >&2
        echo "  iOS keepalive-фикс ядра     : ${ios}" >&2
        echo "" >&2
        echo "  1) Жёсткий  — 1 SYN/с, burst 1  (рекомендация автора)" >&2
        echo "  2) Средний  — 1 SYN/с, burst 3" >&2
        echo "  3) Мягкий   — 2 SYN/с, burst 5" >&2
        echo "  4) iOS keepalive-фикс ядра (60/15/3): переключить вкл/выкл" >&2
        echo "  0) Назад" >&2
        printf '  > ' >&2; read -r c < "$src" || c=0
        case "$c" in
            1) bot_update_config_field reanim_synlimit hard >/dev/null 2>&1; log_success "Жёсткость: жёсткий (1/с, burst 1)." >&2; _diag_reapply_if_reanim ;;
            2) bot_update_config_field reanim_synlimit mid  >/dev/null 2>&1; log_success "Жёсткость: средний (1/с, burst 3)." >&2; _diag_reapply_if_reanim ;;
            3) bot_update_config_field reanim_synlimit soft >/dev/null 2>&1; log_success "Жёсткость: мягкий (2/с, burst 5)." >&2; _diag_reapply_if_reanim ;;
            4) if [ "$ios" = "on" ]; then diagnose_ios_keepalive off; bot_update_config_field reanim_ios_keepalive off >/dev/null 2>&1; \
               else diagnose_ios_keepalive on; bot_update_config_field reanim_ios_keepalive on >/dev/null 2>&1; fi ;;
            0) break ;;
            *) log_error "Неверный выбор" >&2 ;;
        esac
    done
}
