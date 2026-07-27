const $ = (sel) => document.querySelector(sel);
const $$ = (sel) => Array.from(document.querySelectorAll(sel));

const i18n = {
  en: {
    brandSubtitle: "Local Admin",
    navDashboard: "Dashboard",
    navTraffic: "Traffic",
    navKeys: "Keys",
    navBackups: "Backups",
    navLogs: "Logs",
    navSettings: "Settings",
    refresh: "Refresh",
    autoRefresh: "Auto refresh every 5 seconds",
    autoRefreshOn: "Auto refresh is on",
    autoRefreshOff: "Auto refresh is off",
    autoRefreshOffShort: "off",
    themeDark: "Dark",
    themeLight: "Light",
    metricMode: "Mode",
    metricKeys: "Keys",
    metricProxyTraffic: "Proxy traffic",
    metricSiteTraffic: "Site traffic",
    configuredUsers: "configured users",
    systemCpu: "CPU load",
    systemMemory: "Memory",
    systemDisk: "Storage",
    systemUptime: "Server uptime",
    searchKeys: "Search keys",
    keysShown: "keys shown",
    packets: "packets",
    servicesEyebrow: "Services",
    servicesTitle: "Service health",
    servicesHelp: "Systemd service status for telemt, nginx, the bot, the traffic collector and the local admin.",
    runtimeEyebrow: "Runtime",
    runtimeTitle: "telemt summary",
    runtimeHelp: "Runtime data comes from the local telemt API and shows what the proxy engine sees right now.",
    trafficEyebrow: "Traffic",
    trafficTitle: "History",
    keysEyebrow: "Access",
    keysTitle: "User keys",
    backupsEyebrow: "Snapshots",
    backupsTitle: "Backups",
    eventsEyebrow: "Events",
    eventsTitle: "Activity",
    logsEyebrow: "Journal",
    logsTitle: "Logs",
    settingsEyebrow: "Settings",
    settingsTitle: "Panel preferences",
    configEyebrow: "Config",
    configTitle: "Installation state",
    collector: "Collector",
    lastPoint: "Last point",
    historyRows: "History rows",
    collectStats: "Update stats",
    collectStatsHelp: "Run one traffic collection now.",
    repairStats: "Restart collector",
    repairStatsHelp: "Reinstall and restart the background service that writes traffic history.",
    tableTime: "Time",
    tablePeriod: "Period",
    tableStatus: "Status",
    tableProxyDelta: "Proxy delta",
    tableSiteDelta: "Site delta",
    tableProxyTotal: "Proxy total",
    tableSiteTotal: "Site total",
    tableUser: "User",
    tableSecret: "Secret",
    tableLink: "Link",
    tableTraffic: "Traffic",
    ipLimit: "IP limit",
    ipLimitHint: "0 = unlimited",
    saveIpLimit: "OK",
    tableTrafficDelta: "Traffic delta",
    tableTrafficTotal: "Total",
    tableActions: "Actions",
    userPlaceholder: "client-name",
    addKey: "Add key",
    copyLink: "Copy link",
    copySecret: "Copy secret",
    showQr: "QR",
    delete: "Delete",
    enabled: "Enabled",
    disabled: "Disabled",
    applying: "Applying...",
    changesApplyInBackground: "Changes are being applied in the background",
    disableKey: "Disable key",
    enableKey: "Enable key",
    main: "main",
    createBackup: "Create backup",
    restoreBackup: "Restore",
    encryptedRestoreCli: "Encrypted backups are restored from CLI",
    backupScheduleTitle: "Automatic backups",
    backupScheduleLoading: "Loading schedule...",
    backupIncludesTitle: "Backup contents",
    backupIncludesText: "telemt config, IGProxy settings, keys, disabled keys, site, templates, SSL certificates, bot, admin panel and traffic history.",
    scheduleOff: "Off",
    scheduleDaily: "Daily",
    scheduleWeekly: "Weekly",
    scheduleMonthly: "Monthly",
    scheduleSaved: "Schedule saved",
    scheduleNext: "Next run: {value}",
    scheduleDisabled: "Automatic backups are disabled",
    backupRestoreStarted: "Restore started",
    confirmRestoreBackup: "Restore backup",
    loadLogs: "Load",
    panelLanguage: "Panel language",
    theme: "Theme",
    bindAddress: "Bind address",
    dashboard: "Dashboard",
    noKeys: "No keys yet",
    noBackups: "No backups yet",
    noEvents: "No events yet",
    noHistory: "No traffic history yet",
    noTrafficForRange: "No data for this range yet",
    noRuntime: "Runtime data is not available",
    userTrafficEyebrow: "Per user",
    userTrafficTitle: "User traffic",
    selectUserTraffic: "Select a key to see its traffic history",
    openStats: "Stats",
    trafficTotal: "Total",
    currentConnections: "Connections",
    activeIps: "Active IPs",
    recentIps: "Recent IPs",
    trafficRuntimeUnavailable: "Runtime unavailable",
    badConnections: "Bad connections",
    connections: "Connections",
    uptime: "Uptime",
    users: "Users",
    revision: "Revision",
    healthOk: "OK",
    healthError: "Error",
    healthStale: "Stale",
    healthStopped: "Stopped",
    healthNotInstalled: "Not installed",
    healthUnknown: "Unknown",
    statusRunning: "running",
    statusInactive: "inactive",
    statusStopped: "stopped",
    statusFailed: "failed",
    statusNotInstalled: "not installed",
    statusActivating: "activating",
    statusDeactivating: "deactivating",
    statusUnknown: "unknown",
    statsMissing: "Collector is not running",
    statsOk: "Collector is running",
    statsStale: "Snapshot is stale",
    statsError: "Collector error",
    restart: "Restart",
    copied: "Copied",
    copyFailed: "Copy failed",
    keyCreated: "Key created",
    keyDeleted: "Key deleted",
    backupCreated: "Backup created",
    qrUnavailable: "QR code is unavailable",
    serviceRestarted: "Service restarted",
    statsRepaired: "Collector restarted",
    statsCollected: "Statistics collected",
    confirmDelete: "Delete key",
    confirmRestart: "Restart",
    invalidUser: "Use latin letters, digits, _, . or -",
    loading: "Loading...",
    never: "never",
    lightTheme: "Light",
    darkTheme: "Dark",
    configMode: "Mode",
    configDomain: "Domain",
    configSiteStatus: "Site check",
    configTemplate: "Template",
    configVersion: "Version",
    siteOk: "Site 200 OK",
    siteHttp: "Site HTTP",
    siteMissing: "Domain is not configured",
    siteInvalid: "Invalid domain",
    siteError: "Site check failed",
    siteNotChecked: "Site check pending",
    logsLines: "lines",
    logsNoData: "No log lines",
    languageSaved: "Language saved",
    keyEnabled: "Key enabled",
    keyDisabled: "Key disabled",
    ipLimitSaved: "IP limit saved",
    visualTitle: "Port 443 map",
    visualText: "Shows the public 443 listener and services routed behind it, including the website on local nginx.",
    port443Checked: "checked",
    port443NoListeners: "No 443 listeners found",
    port443Listeners: "listeners",
    port443Routes: "routed",
    port443Error: "Port check failed",
    port443Public: "public",
    port443Configured: "telemt: {port}",
    port443PublicSection: "Public 443",
    port443BehindSection: "Behind 443",
    port443NoRoutes: "No routed services detected",
    port443Via: "via {value}",
    roleMtproxy: "MTProxy",
    roleEdge: "443 Edge",
    roleSite: "Website",
    roleXray: "Xray / 3x-ui",
    roleAmneziawg: "AmneziaWG",
    roleOther: "Other",
    range15m: "15 min",
    range1h: "1 hour",
    range24h: "24 hours",
    rangeMonth: "Month",
    viewChart: "Chart",
    viewRows: "Rows",
    chartMax: "max {value} per interval",
    chartProxy: "proxy",
    chartSite: "site",
    encrypted: "encrypted",
    ariaAdminSections: "Admin sections",
    ariaMenu: "Open menu",
    ariaLanguage: "Language",
    ariaClose: "Close",
    ariaTrafficHistory: "Traffic history",
    ariaTrafficRange: "Traffic range",
    ariaTrafficView: "Traffic view",
    qrEyebrow: "QR import",
    qrTitle: "Scan Telegram proxy",
    pageDashboardTitle: "Dashboard",
    pageDashboardKicker: "Local Admin",
    pageTrafficTitle: "Traffic",
    pageTrafficKicker: "Statistics",
    pageKeysTitle: "Keys",
    pageKeysKicker: "Access",
    pageBackupsTitle: "Backups",
    pageBackupsKicker: "Migration",
    pageLogsTitle: "Logs",
    pageLogsKicker: "Journal",
    pageSettingsTitle: "Settings",
    pageSettingsKicker: "Preferences",
  },
  ru: {
    brandSubtitle: "Локальная админка",
    navDashboard: "Обзор",
    navTraffic: "Трафик",
    navKeys: "Ключи",
    navBackups: "Бекапы",
    navLogs: "Логи",
    navSettings: "Настройки",
    refresh: "Обновить",
    autoRefresh: "Автообновление каждые 5 секунд",
    autoRefreshOn: "Автообновление включено",
    autoRefreshOff: "Автообновление выключено",
    autoRefreshOffShort: "выкл",
    themeDark: "Тёмная",
    themeLight: "Светлая",
    metricMode: "Схема публикации",
    metricKeys: "Ключи",
    metricProxyTraffic: "Трафик прокси",
    metricSiteTraffic: "Трафик сайта",
    configuredUsers: "настроенных пользователей",
    systemCpu: "Нагрузка CPU",
    systemMemory: "Память",
    systemDisk: "Хранилище",
    systemUptime: "Аптайм сервера",
    searchKeys: "Поиск ключей",
    keysShown: "ключей показано",
    packets: "пакетов",
    servicesEyebrow: "Сервисы",
    servicesTitle: "Состояние служб",
    servicesHelp: "Статус systemd-служб: telemt, nginx, бот, сборщик трафика и локальная админка.",
    runtimeEyebrow: "Среда выполнения",
    runtimeTitle: "Сводка telemt",
    runtimeHelp: "Данные среды выполнения берутся из локального API telemt и показывают, что ядро прокси видит прямо сейчас.",
    trafficEyebrow: "Трафик",
    trafficTitle: "История",
    keysEyebrow: "Доступ",
    keysTitle: "Ключи пользователей",
    backupsEyebrow: "Снимки",
    backupsTitle: "Бекапы",
    eventsEyebrow: "События",
    eventsTitle: "Активность",
    logsEyebrow: "Журнал",
    logsTitle: "Логи",
    settingsEyebrow: "Настройки",
    settingsTitle: "Параметры панели",
    configEyebrow: "Конфиг",
    configTitle: "Состояние установки",
    collector: "Сборщик",
    lastPoint: "Последняя точка",
    historyRows: "Строк истории",
    collectStats: "Обновить статистику",
    collectStatsHelp: "Запустить один сбор трафика прямо сейчас.",
    repairStats: "Перезапустить сборщик",
    repairStatsHelp: "Переустановить и перезапустить фоновую службу, которая пишет историю трафика.",
    tableTime: "Время",
    tablePeriod: "Период",
    tableStatus: "Статус",
    tableProxyDelta: "Прирост прокси",
    tableSiteDelta: "Прирост сайта",
    tableProxyTotal: "Всего прокси",
    tableSiteTotal: "Всего по сайту",
    tableUser: "Пользователь",
    tableSecret: "Секрет",
    tableLink: "Ссылка",
    tableTraffic: "Трафик",
    ipLimit: "Лимит IP",
    ipLimitHint: "0 = безлимит",
    saveIpLimit: "OK",
    tableTrafficDelta: "Прирост трафика",
    tableTrafficTotal: "Всего",
    tableActions: "Действия",
    userPlaceholder: "client-name",
    addKey: "Добавить ключ",
    copyLink: "Копировать ссылку",
    copySecret: "Копировать секрет",
    showQr: "QR",
    delete: "Удалить",
    enabled: "Включён",
    disabled: "Отключён",
    applying: "Применяется...",
    changesApplyInBackground: "Изменения применяются в фоне",
    disableKey: "Отключить ключ",
    enableKey: "Включить ключ",
    main: "основной",
    createBackup: "Создать бекап",
    restoreBackup: "Восстановить",
    encryptedRestoreCli: "Зашифрованные бекапы восстанавливаются через CLI",
    backupScheduleTitle: "Автобекапы",
    backupScheduleLoading: "Загрузка расписания...",
    backupIncludesTitle: "Что входит в бекап",
    backupIncludesText: "конфиг telemt, настройки IGProxy, ключи, отключённые ключи, сайт, шаблоны, SSL-сертификаты, бот, админка и история трафика.",
    scheduleOff: "Выкл",
    scheduleDaily: "Каждый день",
    scheduleWeekly: "Каждую неделю",
    scheduleMonthly: "Каждый месяц",
    scheduleSaved: "Расписание сохранено",
    scheduleNext: "Следующий запуск: {value}",
    scheduleDisabled: "Автобекапы отключены",
    backupRestoreStarted: "Восстановление запущено",
    confirmRestoreBackup: "Восстановить бекап",
    loadLogs: "Загрузить",
    panelLanguage: "Язык панели",
    theme: "Тема",
    bindAddress: "Адрес привязки",
    dashboard: "Обзор",
    noKeys: "Ключей пока нет",
    noBackups: "Бекапов пока нет",
    noEvents: "Событий пока нет",
    noHistory: "Истории трафика пока нет",
    noTrafficForRange: "За этот период данных пока нет",
    noRuntime: "Данные среды выполнения недоступны",
    userTrafficEyebrow: "По пользователю",
    userTrafficTitle: "Трафик ключа",
    selectUserTraffic: "Выберите ключ, чтобы увидеть историю трафика",
    openStats: "Статистика",
    trafficTotal: "Всего",
    currentConnections: "Подключения",
    activeIps: "Активные IP",
    recentIps: "Недавние IP",
    trafficRuntimeUnavailable: "Runtime недоступен",
    badConnections: "Ошибочные подключения",
    connections: "Подключения",
    uptime: "Аптайм",
    users: "Пользователи",
    revision: "Ревизия",
    healthOk: "OK",
    healthError: "Ошибка",
    healthStale: "Устарело",
    healthStopped: "Остановлено",
    healthNotInstalled: "Не установлен",
    healthUnknown: "Неизвестно",
    statusRunning: "работает",
    statusInactive: "неактивен",
    statusStopped: "остановлен",
    statusFailed: "ошибка",
    statusNotInstalled: "не установлен",
    statusActivating: "запускается",
    statusDeactivating: "останавливается",
    statusUnknown: "неизвестно",
    statsMissing: "Сборщик не запущен",
    statsOk: "Сборщик работает",
    statsStale: "Снимок устарел",
    statsError: "Ошибка сборщика",
    restart: "Перезапустить",
    copied: "Скопировано",
    copyFailed: "Не удалось скопировать",
    keyCreated: "Ключ создан",
    keyDeleted: "Ключ удалён",
    backupCreated: "Бекап создан",
    qrUnavailable: "QR-код недоступен",
    serviceRestarted: "Сервис перезапущен",
    statsRepaired: "Сборщик перезапущен",
    statsCollected: "Статистика собрана",
    confirmDelete: "Удалить ключ",
    confirmRestart: "Перезапустить",
    invalidUser: "Используйте латиницу, цифры, _, . или -",
    loading: "Загрузка...",
    never: "никогда",
    lightTheme: "Светлая",
    darkTheme: "Тёмная",
    configMode: "Схема публикации",
    configDomain: "Домен",
    configSiteStatus: "Проверка сайта",
    configTemplate: "Шаблон",
    configVersion: "Версия",
    siteOk: "Сайт 200 OK",
    siteHttp: "Сайт HTTP",
    siteMissing: "Домен не настроен",
    siteInvalid: "Некорректный домен",
    siteError: "Проверка сайта не прошла",
    siteNotChecked: "Проверка сайта ожидает",
    logsLines: "строк",
    logsNoData: "Строк логов нет",
    languageSaved: "Язык сохранён",
    keyEnabled: "Ключ включён",
    keyDisabled: "Ключ отключён",
    ipLimitSaved: "Лимит IP сохранён",
    visualTitle: "Карта порта 443",
    visualText: "Показывает публичного слушателя 443 и сервисы, которые живут за ним, включая сайт на локальном nginx.",
    port443Checked: "проверено",
    port443NoListeners: "Слушателей 443 не найдено",
    port443Listeners: "слушателей",
    port443Routes: "за 443",
    port443Error: "Проверка порта не удалась",
    port443Public: "публичный",
    port443Configured: "telemt: {port}",
    port443PublicSection: "Публичный 443",
    port443BehindSection: "За портом 443",
    port443NoRoutes: "Маршрутизируемых сервисов не найдено",
    port443Via: "через {value}",
    roleMtproxy: "MTProxy",
    roleEdge: "443 Edge",
    roleSite: "Сайт",
    roleXray: "Xray / 3x-ui",
    roleAmneziawg: "AmneziaWG",
    roleOther: "Другое",
    range15m: "15 мин",
    range1h: "1 час",
    range24h: "24 часа",
    rangeMonth: "Месяц",
    viewChart: "График",
    viewRows: "Строки",
    chartMax: "макс. {value} за интервал",
    chartProxy: "прокси",
    chartSite: "сайт",
    modePro: "Свой домен и сайт",
    modeProHelp: "Прокси маскируется под ваш сайт с доменом и TLS.",
    modeLite: "Только прокси",
    modeLiteHelp: "Прокси работает без собственного сайта и использует внешний адрес маскировки.",
    modeUnknown: "Не определена",
    chartPeriodTraffic: "Передано за период",
    chartPeak: "Пиковый интервал",
    chartPoints: "Точек на графике",
    chartExplanation: "Высота точки — трафик, переданный за один интервал сбора. Это не накопительный итог.",
    chartProxyPeriod: "Прокси за период",
    chartSitePeriod: "Сайт за период",
    filterKeys: "Фильтр ключей",
    onlineNow: "Сейчас в сети",
    totalTraffic: "Общий трафик",
    noLimit: "Без лимита",
    showSecret: "Показать",
    hideSecret: "Скрыть",
    backupLast: "Последний бекап",
    backupCount: "Хранится копий",
    backupSize: "Общий размер",
    backupNext: "Следующий запуск",
    backupReady: "готов к восстановлению",
    logHuman: "Понятно",
    logRaw: "Как есть",
    logRawDetails: "Исходная строка",
    logNoEvents: "Понятных событий в выбранном фрагменте нет",
    activeServices: "Службы работают",
    activeConnections: "Текущие подключения",
    activeAddresses: "Активные IP",
    diskFree: "Свободно на диске",
    encrypted: "зашифровано",
    ariaAdminSections: "Разделы админки",
    ariaMenu: "Открыть меню",
    ariaLanguage: "Язык",
    ariaClose: "Закрыть",
    ariaTrafficHistory: "История трафика",
    ariaTrafficRange: "Период трафика",
    ariaTrafficView: "Вид трафика",
    qrEyebrow: "QR-импорт",
    qrTitle: "Сканирование прокси Telegram",
    pageDashboardTitle: "Обзор",
    pageDashboardKicker: "Локальная админка",
    pageTrafficTitle: "Трафик",
    pageTrafficKicker: "Статистика",
    pageKeysTitle: "Ключи",
    pageKeysKicker: "Доступ",
    pageBackupsTitle: "Бекапы",
    pageBackupsKicker: "Переезд",
    pageLogsTitle: "Логи",
    pageLogsKicker: "Журнал",
    pageSettingsTitle: "Настройки",
    pageSettingsKicker: "Параметры",
  },
};

const AUTO_REFRESH_MS = 5000;

const state = {
  overview: null,
  stats: null,
  users: [],
  events: [],
  lang: "ru",
  page: "dashboard",
  theme: document.documentElement.dataset.theme || "light",
  trafficRange: "1h",
  trafficView: "chart",
  trafficMetric: "rate",
  trafficSmooth: true,
  trafficProxySeries: true,
  trafficSiteSeries: true,
  trafficHideIdle: false,
  trafficTableOrder: "newest",
  trafficLoading: false,
  userTrafficUser: "",
  userTrafficRange: "1h",
  userTrafficView: "chart",
  userTrafficMetric: "rate",
  userTrafficSmooth: true,
  userTraffic: null,
  userTrafficLoading: false,
  backupSchedule: null,
  qrLink: "",
  userSearch: "",
  userFilter: "all",
  revealedUsers: new Set(),
  pendingUsers: new Set(),
  logView: "human",
  logsPayload: null,
  refreshingAll: false,
  autoRefreshEnabled: localStorage.getItem("gotelegram-auto-refresh") !== "0",
  autoRefreshMs: Number(localStorage.getItem("igproxy-refresh-ms") || AUTO_REFRESH_MS),
  themeMode: localStorage.getItem("igproxy-theme-mode") || "system",
  siteSettings: null,
  selectedSitePreset: "",
};

const t = (key) => (i18n[state.lang] && i18n[state.lang][key]) || i18n.en[key] || key;

const trafficRanges = ["15m", "1h", "6h", "24h", "7d", "month"];
let autoRefreshTimer = null;

const fmtBytes = (value = 0) => {
  const units = ["B", "KB", "MB", "GB", "TB"];
  let n = Number(value) || 0;
  let i = 0;
  while (n >= 1024 && i < units.length - 1) {
    n /= 1024;
    i += 1;
  }
  return `${n.toFixed(i === 0 ? 0 : 1)} ${units[i]}`;
};

const fmtDate = (epoch) => {
  if (!epoch) return t("never");
  return new Date(epoch * 1000).toLocaleString(state.lang === "ru" ? "ru-RU" : "en-US");
};

const fmtDuration = (seconds = 0) => {
  let value = Math.max(0, Math.floor(Number(seconds) || 0));
  const days = Math.floor(value / 86400);
  value %= 86400;
  const hours = Math.floor(value / 3600);
  value %= 3600;
  const minutes = Math.floor(value / 60);
  if (days) return `${days}d ${hours}h`;
  if (hours) return `${hours}h ${minutes}m`;
  return `${minutes}m`;
};

const setGauge = (selector, value) => {
  const normalized = Math.max(0, Math.min(100, Number(value) || 0));
  const element = $(selector);
  if (element) element.style.setProperty("--value", normalized);
  return `${normalized.toFixed(normalized >= 10 ? 0 : 1)}%`;
};

const smoothSvgPath = (points, key, toX, toY) => {
  const coords = points.map((point, index) => ({
    x: toX(index),
    y: toY(Number(point[key]) || 0),
  }));
  if (!coords.length) return "";
  if (coords.length === 1) return `M${coords[0].x.toFixed(1)},${coords[0].y.toFixed(1)}`;
  const minY = Math.min(...coords.map((point) => point.y));
  const maxY = Math.max(...coords.map((point) => point.y));
  const clampY = (value) => Math.max(minY, Math.min(maxY, value));
  let path = `M${coords[0].x.toFixed(1)},${coords[0].y.toFixed(1)}`;
  for (let index = 0; index < coords.length - 1; index += 1) {
    const p0 = coords[Math.max(0, index - 1)];
    const p1 = coords[index];
    const p2 = coords[index + 1];
    const p3 = coords[Math.min(coords.length - 1, index + 2)];
    const c1x = p1.x + (p2.x - p0.x) / 6;
    const c1y = clampY(p1.y + (p2.y - p0.y) / 6);
    const c2x = p2.x - (p3.x - p1.x) / 6;
    const c2y = clampY(p2.y - (p3.y - p1.y) / 6);
    path += ` C${c1x.toFixed(1)},${c1y.toFixed(1)} ${c2x.toFixed(1)},${c2y.toFixed(1)} ${p2.x.toFixed(1)},${p2.y.toFixed(1)}`;
  }
  return path;
};

const escapeHtml = (value) => String(value ?? "").replace(/[&<>"']/g, (ch) => ({
  "&": "&amp;",
  "<": "&lt;",
  ">": "&gt;",
  '"': "&quot;",
  "'": "&#039;",
})[ch]);

const escapeAttr = (value) => escapeHtml(value).replace(/`/g, "&#096;");

const stableHtml = (element, html, signature = html) => {
  if (!element) return false;
  const next = String(signature);
  if (element.dataset.renderSignature === next) return false;
  element.innerHTML = html;
  element.dataset.renderSignature = next;
  return true;
};

const modePresentation = (mode) => {
  if (String(mode).toLowerCase() === "pro") return { label: t("modePro"), help: t("modeProHelp") };
  if (String(mode).toLowerCase() === "lite") return { label: t("modeLite"), help: t("modeLiteHelp") };
  return { label: t("modeUnknown"), help: "" };
};

const compactTime = (epoch) => {
  if (!epoch) return "--";
  return new Date(Number(epoch) * 1000).toLocaleTimeString("ru-RU", { hour: "2-digit", minute: "2-digit" });
};

const fmtSystemdTime = (value) => {
  const raw = String(value || "").trim();
  if (!raw || raw === "n/a") return "";
  const parsed = new Date(raw.replace(/^[A-Za-z]{3}\s+/, "").replace(/\s+UTC$/, "Z"));
  if (Number.isNaN(parsed.getTime())) return raw;
  return `${parsed.toLocaleString("ru-RU", { timeZone: "UTC", day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" })} UTC`;
};

const toast = (message) => {
  const el = $("#toast");
  el.textContent = message;
  el.classList.add("show");
  clearTimeout(toast._timer);
  toast._timer = setTimeout(() => el.classList.remove("show"), 2800);
};

const addEvent = (title, detail = "") => {
  state.events.unshift({ title, detail, time: new Date() });
  state.events = state.events.slice(0, 10);
  renderEvents();
};

function updateAutoRefreshToggle() {
  const button = $("#autoRefreshToggle");
  if (!button) return;
  button.classList.toggle("active", state.autoRefreshEnabled);
  button.setAttribute("aria-pressed", String(state.autoRefreshEnabled));
  button.title = state.autoRefreshEnabled ? t("autoRefreshOn") : t("autoRefreshOff");
  const label = button.querySelector(".auto-refresh-state");
  if (label) label.textContent = state.autoRefreshEnabled ? `${state.autoRefreshMs / 1000}s` : t("autoRefreshOffShort");
  $$("[data-refresh-ms]").forEach((item) => {
    item.classList.toggle("active", Number(item.dataset.refreshMs) === (state.autoRefreshEnabled ? state.autoRefreshMs : 0));
  });
}

function syncAutoRefreshTimer() {
  if (autoRefreshTimer) {
    clearInterval(autoRefreshTimer);
    autoRefreshTimer = null;
  }
  if (!state.autoRefreshEnabled) return;
  autoRefreshTimer = setInterval(() => {
    refreshAll({ silent: true }).catch(() => {});
  }, state.autoRefreshMs);
}

function setAutoRefresh(enabled, interval = state.autoRefreshMs) {
  state.autoRefreshEnabled = Boolean(enabled);
  state.autoRefreshMs = Math.max(5000, Number(interval) || 5000);
  localStorage.setItem("gotelegram-auto-refresh", state.autoRefreshEnabled ? "1" : "0");
  localStorage.setItem("igproxy-refresh-ms", String(state.autoRefreshMs));
  updateAutoRefreshToggle();
  syncAutoRefreshTimer();
}

async function api(path, options = {}) {
  const headers = {
    "Accept": "application/json",
    "X-GoTelegram-Admin": "1",
    ...(options.headers || {}),
  };
  if (options.body && !headers["Content-Type"]) headers["Content-Type"] = "application/json";
  const res = await fetch(path, { ...options, headers, credentials: "same-origin" });
  const data = await res.json().catch(() => ({}));
  if (!res.ok || data.ok === false) throw new Error(data.error || `HTTP ${res.status}`);
  return data.data ?? data;
}

function applyI18n() {
  state.lang = "ru";
  document.documentElement.lang = "ru";
  $$("[data-i18n]").forEach((el) => {
    el.textContent = t(el.dataset.i18n);
  });
  $$("[data-i18n-placeholder]").forEach((el) => {
    el.placeholder = t(el.dataset.i18nPlaceholder);
  });
  $$("[data-i18n-title]").forEach((el) => {
    el.title = t(el.dataset.i18nTitle);
  });
  $$("[data-i18n-aria-label]").forEach((el) => {
    el.setAttribute("aria-label", t(el.dataset.i18nAriaLabel));
  });
  $("#themeToggle").textContent = state.theme === "dark" ? t("themeLight") : t("themeDark");
  $("#settingsTheme").textContent = state.theme === "dark" ? t("darkTheme") : t("lightTheme");
  if (!state.overview) {
    $("#visualTitle").textContent = t("visualTitle");
    $("#visualText").textContent = t("visualText");
  }
  updateTrafficControls();
  updateUserTrafficControls();
  renderBackupSchedule();
  updatePageTitle();
  updateAutoRefreshToggle();
}

function setTheme(theme) {
  state.theme = theme === "dark" ? "dark" : "light";
  document.documentElement.dataset.theme = state.theme;
  localStorage.setItem("gotelegram-theme", state.theme);
  applyI18n();
  if (state.overview) renderStats();
  if (state.userTraffic) renderUserTraffic();
}

function setThemeMode(mode) {
  state.themeMode = ["system", "dark", "light"].includes(mode) ? mode : "system";
  localStorage.setItem("igproxy-theme-mode", state.themeMode);
  const systemDark = matchMedia("(prefers-color-scheme: dark)").matches;
  setTheme(state.themeMode === "system" ? (systemDark ? "dark" : "light") : state.themeMode);
  $$("[data-theme-mode]").forEach((item) => item.classList.toggle("active", item.dataset.themeMode === state.themeMode));
}

function setPage(page, push = true) {
  const next = $(`[data-page="${page}"]`) ? page : "dashboard";
  state.page = next;
  $$(".page-panel").forEach((panel) => panel.classList.toggle("active", panel.dataset.page === next));
  $$("[data-nav]").forEach((item) => item.classList.toggle("active", item.dataset.nav === next));
  $("#sidebar").classList.remove("open");
  updatePageTitle();
  if (push && location.hash !== `#${next}`) {
    history.replaceState(null, "", `#${next}`);
  }
  requestAnimationFrame(() => {
    window.scrollTo({ top: 0, behavior: push ? "smooth" : "auto" });
  });
  if (next === "traffic") {
    refreshStats().catch((err) => toast(err.message));
  } else if (next === "keys") {
    ensureUserTrafficSelection();
    renderUserTraffic();
    if (state.userTrafficUser) refreshUserTraffic().catch((err) => toast(err.message));
  }
}

function updatePageTitle() {
  const cap = state.page.charAt(0).toUpperCase() + state.page.slice(1);
  $("#pageTitle").textContent = t(`page${cap}Title`);
  $("#pageKicker").textContent = t(`page${cap}Kicker`);
}

function updateLanguageFromOverview(data) {
  state.lang = "ru";
}

function statusLabel(status) {
  const key = `status${String(status || "unknown").replace(/(^|_)([a-z])/g, (_, __, ch) => ch.toUpperCase())}`;
  const label = t(key);
  return label === key ? (status || t("healthUnknown")) : label;
}

function healthLabel(health) {
  const labels = {
    ok: t("healthOk"),
    error: t("healthError"),
    stale: t("healthStale"),
    stopped: t("healthStopped"),
    not_installed: t("healthNotInstalled"),
  };
  return labels[health] || t("healthUnknown");
}

function renderServices(services = {}) {
  const site = state.overview?.site_status || {};
  const runtimeOk = Boolean(runtimeData());
  const items = [
    { key: "telemt", label: "MTProxy · telemt", api: "telemt", restart: true },
    { key: "nginx", label: "Публичный сайт · nginx", api: "nginx", restart: true },
    { key: "bot", label: "Telegram-бот", api: "gotelegram-bot", restart: true },
    { key: "stats", label: "Сбор статистики", api: "gotelegram-stats", restart: true },
    { key: "site", label: "Доступность сайта", status: site.ok ? "running" : (site.checked ? "failed" : "unknown") },
    { key: "runtime", label: "telemt API", status: runtimeOk ? "running" : "failed" },
  ];
  const html = items.map((item) => {
    const status = item.status || services[item.key] || "unknown";
    const disabled = !item.restart || status === "not_installed";
    return `<article class="service status-${escapeAttr(status)}">
      <div>
        <strong>${escapeHtml(item.label)}</strong>
        <span><i></i>${escapeHtml(statusLabel(status))}</span>
      </div>
      ${item.restart
        ? `<button class="soft" data-restart="${escapeAttr(item.api)}" ${disabled ? "disabled" : ""}>${escapeHtml(t("restart"))}</button>`
        : `<button class="soft" data-dashboard-jump="${item.key === "site" ? "settings" : "logs"}">Подробнее</button>`}
    </article>`;
  }).join("");
  stableHtml($("#services"), html, JSON.stringify([services, site.ok, runtimeOk]));
}

function runtimeData() {
  const raw = state.overview?.runtime_summary;
  if (!raw || typeof raw !== "object") return null;
  return raw.data && typeof raw.data === "object" ? raw.data : raw;
}

function renderRuntime() {
  const data = runtimeData();
  if (!data) {
    stableHtml($("#runtimeCards"), `<div class="empty">${escapeHtml(t("noRuntime"))}</div>`, "empty");
    stableHtml($("#runtimeIssues"), "", "empty");
    return;
  }
  const revision = String(data.revision || state.overview?.runtime_summary?.revision || "--");
  const total = Number(data.connections_total) || 0;
  const badTotal = Number(data.connections_bad_total) || 0;
  const badRatio = total ? Math.min(100, badTotal / total * 100) : 0;
  const liveConnections = state.users.reduce((sum, user) => sum + (Number(user.traffic?.current_connections) || 0), 0);
  const activeUsers = state.users.filter((user) => Number(user.traffic?.current_connections) > 0).length;
  const cards = [
    ["Состояние ядра", badRatio < 5 ? "Стабильно" : (badRatio < 20 ? "Есть сбои" : "Требует внимания"), badRatio < 5 ? "good" : "warn", `${badRatio.toFixed(1)}% неуспешных соединений`],
    ["Сейчас через прокси", liveConnections, liveConnections ? "good" : "", `${activeUsers} активных ключей`],
    ["Обработано соединений", total, "", `${badTotal} завершились ошибкой`],
    [t("uptime"), fmtDuration(data.uptime_seconds), "good", `ревизия ${revision.slice(0, 10)}`],
  ];
  stableHtml($("#runtimeCards"), cards.map(([label, value, level, hint]) => `
    <article class="runtime-card ${escapeAttr(level)}">
      <span>${escapeHtml(label)}</span>
      <strong>${escapeHtml(value)}</strong>
      <small>${escapeHtml(hint)}</small>
    </article>
  `).join(""), JSON.stringify(cards));
  const bad = Array.isArray(data.connections_bad_by_class) ? data.connections_bad_by_class : [];
  const explanations = {
    client: "Клиент закрыл соединение или прислал неподходящий запрос.",
    telegram: "Telegram DC временно не ответил или разорвал upstream.",
    timeout: "Соединение не успело завершиться за допустимое время.",
    protocol: "Ошибка протокола или несовместимый клиент.",
    unknown: "Ядро не смогло точнее классифицировать причину.",
  };
  const advice = badRatio >= 20
    ? "Доля ошибок высокая: сначала откройте логи telemt, затем проверьте доступность Telegram DC. Перезапуск используйте, если ошибки продолжают расти."
    : badRatio >= 5
      ? "Есть заметные сбои. Сопоставьте их время с графиком трафика и журналом telemt."
      : "Ядро работает стабильно. Если клиенты жалуются на доступ, проверьте конкретный ключ и его активные IP.";
  const issues = bad.length ? `
    <div class="runtime-issues-head"><strong>Причины сбоев</strong><span>накопительно с запуска</span></div>
    ${bad.slice().sort((a, b) => Number(b.total || 0) - Number(a.total || 0)).slice(0, 6).map((item) => {
      const rawClass = String(item.class || "unknown");
      const key = Object.keys(explanations).find((candidate) => rawClass.toLowerCase().includes(candidate)) || "unknown";
      const share = badTotal ? Math.min(100, Number(item.total || 0) / badTotal * 100) : 0;
      return `<div class="issue" title="${escapeAttr(rawClass)}">
        <div><strong>${escapeHtml(rawClass)}</strong><small>${escapeHtml(explanations[key])}</small></div>
        <div class="issue-value"><strong>${escapeHtml(item.total ?? 0)}</strong><span style="--issue-share:${share}%"></span></div>
      </div>`;
    }).join("")}` : `<div class="runtime-clean">Ошибок по классам нет</div>`;
  stableHtml($("#runtimeIssues"), `${issues}
    <div class="runtime-advice">
      <div><strong>Что делать</strong><p>${escapeHtml(advice)}</p></div>
      <div class="runtime-actions">
        <button class="soft" data-dashboard-jump="logs">Открыть логи telemt</button>
        <button class="soft" data-dashboard-jump="traffic">Сверить с трафиком</button>
        <button class="soft danger-soft" data-restart="telemt">Перезапустить telemt</button>
      </div>
    </div>`, JSON.stringify([bad, badTotal, advice]));
}

function siteStatusText(site = {}) {
  if (!site.host) return t("siteMissing");
  if (site.error === "invalid_domain") return t("siteInvalid");
  if (site.ok) return t("siteOk");
  if (site.checked && site.http_code) return `${t("siteHttp")} ${site.http_code}`;
  if (site.error) return t("siteError");
  return t("siteNotChecked");
}

function siteStatusClass(site = {}) {
  if (site.ok) return "ok";
  if (!site.host || !site.checked) return "warn";
  return "error";
}

function renderSiteStatus() {
  const cfg = state.overview?.config || {};
  const site = state.overview?.site_status || {};
  $("#metricDomain").textContent = site.host || cfg.domain || cfg.mask_host || "--";
  const statusEl = $("#siteStatus");
  statusEl.textContent = siteStatusText(site);
  statusEl.className = `metric-status ${siteStatusClass(site)}`;
  statusEl.title = site.url || "";
  const proxyRunning = state.overview?.services?.telemt === "running";
  const proxyEl = $("#proxyStatus");
  proxyEl.textContent = proxyRunning ? "Прокси работает" : "Прокси остановлен";
  proxyEl.className = `metric-status ${proxyRunning ? "ok" : "error"}`;
  const bothOk = proxyRunning && site.ok;
  $("#metricAvailability").textContent = bothOk ? "Оба работают" : (proxyRunning || site.ok ? "Частично доступно" : "Недоступно");
}

function renderOperationsSummary() {
  const services = Object.fromEntries(
    Object.entries(state.overview?.services || {}).filter(([name]) => name !== "admin")
  );
  const system = state.overview?.system || {};
  const running = Object.values(services).filter((status) => status === "running").length;
  const totalServices = Object.keys(services).length;
  const connections = state.users.reduce((sum, user) => sum + (Number(user.traffic?.current_connections) || 0), 0);
  const activeIps = state.users.reduce((sum, user) => sum + (Number(user.traffic?.active_unique_ips) || 0), 0);
  const tiles = [
    [t("activeServices"), `${running} / ${totalServices}`, running === totalServices ? "good" : "warn", totalServices ? statusLabel(running === totalServices ? "running" : "inactive") : "--"],
    [t("activeConnections"), connections, connections ? "good" : "", t("onlineNow")],
    [t("activeAddresses"), activeIps, activeIps ? "good" : "", `${state.users.filter((user) => user.enabled).length} ${t("enabled").toLowerCase()}`],
    [t("diskFree"), fmtBytes(system.disk?.free), Number(system.disk?.percent) > 85 ? "bad" : "good", `${setGauge("#diskGauge", system.disk?.percent)} ${t("systemDisk").toLowerCase()}`],
  ];
  stableHtml($("#operationsStrip"), tiles.map(([label, value, level, hint]) => `
    <article class="summary-tile ${escapeAttr(level)}">
      <span>${escapeHtml(label)}</span>
      <strong>${escapeHtml(value)}</strong>
      <small>${escapeHtml(hint)}</small>
    </article>
  `).join(""), JSON.stringify(tiles));
}

function roleLabel(role) {
  const key = `role${String(role || "other").replace(/(^|_)([a-z])/g, (_, __, ch) => ch.toUpperCase())}`;
  const label = t(key);
  return label === key ? t("roleOther") : label;
}

function renderPort443(payload = {}) {
  const listeners = Array.isArray(payload.listeners) ? payload.listeners : [];
  const routes = Array.isArray(payload.routes) ? payload.routes : [];
  const summary = $("#port443Summary");
  const list = $("#port443List");
  const configuredPort = Number(payload.configured_port) || 443;
  $("#port443Number").textContent = String(configuredPort);
  $("#visualTitle").textContent = `Порт ${configuredPort}`;
  $("#visualText").textContent = "Публичная точка входа и сервисы за ней.";
  $("#port443Configured").textContent = configuredPort === 443 ? t("port443Public") : t("port443Configured").replace("{port}", configuredPort);
  if (payload.error) {
    summary.textContent = t("port443Error");
    summary.className = "port-status error";
    $("#portHealthBadge").textContent = "Ошибка";
    $("#portHealthBadge").className = "port-health-badge error";
    $("#portIngressState").textContent = "Ошибка";
  } else if (!listeners.length) {
    summary.textContent = t("port443NoListeners");
    summary.className = "port-status warn";
    $("#portHealthBadge").textContent = "Нет слушателя";
    $("#portHealthBadge").className = "port-health-badge warn";
    $("#portIngressState").textContent = "Не слушает";
  } else {
    summary.textContent = `${listeners.length} ${t("port443Listeners")}${routes.length ? ` · ${routes.length} ${t("port443Routes")}` : ""}`;
    summary.className = "port-status ok";
    $("#portHealthBadge").textContent = routes.length ? "Прокси и сайт работают" : "Прокси работает";
    $("#portHealthBadge").className = "port-health-badge ok";
    $("#portIngressState").textContent = routes.length ? "Доступно" : "Только прокси";
  }
  const listenerHtml = listeners.length ? listeners.map((item) => {
    const title = `${item.proto || ""} ${item.address || ""} · ${item.process || "unknown"}${item.pid ? ` · pid ${item.pid}` : ""}`;
    return `<article class="port-listener role-${escapeAttr(item.role || "other")}" title="${escapeAttr(title)}">
      <div>
        <strong>${escapeHtml(roleLabel(item.role))}</strong>
        <span>${escapeHtml(item.process || "unknown")} · принимает подключения</span>
      </div>
      <small>${escapeHtml(item.proto || "--")} · порт ${escapeHtml(configuredPort)}</small>
    </article>`;
  }).join("") : `<div class="port-empty">${escapeHtml(payload.error || t("port443NoListeners"))}</div>`;
  const routeHtml = routes.length ? routes.map((item) => {
    const via = item.via ? t("port443Via").replace("{value}", item.via) : "";
    const title = `${item.public || ""} → ${item.target || ""} · ${item.process || ""}`;
    return `<article class="port-listener role-${escapeAttr(item.role || "other")}" title="${escapeAttr(title)}">
      <div>
        <strong>${escapeHtml(roleLabel(item.role))}</strong>
        <span>${escapeHtml(item.process || "unknown")}${item.status ? ` · ${escapeHtml(statusLabel(item.status))}` : ""}</span>
      </div>
      <small>${item.status ? escapeHtml(statusLabel(item.status)) : "маршрут настроен"}</small>
    </article>`;
  }).join("") : `<div class="port-empty">${escapeHtml(t("port443NoRoutes"))}</div>`;
  list.innerHTML = `
    <div class="port-section-label">${escapeHtml(`Публичный порт ${configuredPort}`)}</div>
    ${listenerHtml}
    <div class="port-section-label">${escapeHtml(`За портом ${configuredPort}`)}</div>
    ${routeHtml}
  `;
}

function renderOverview() {
  const data = state.overview;
  if (!data) return;
  const cfg = data.config || {};
  const stats = data.stats_current || {};
  const system = data.system || {};
  const memory = system.memory || {};
  const disk = system.disk || {};
  const bind = data.admin_bind || {};
  $("#sidebarVersion").textContent = `v${data.version || "--"}`;
  $("#sidebarBind").textContent = `${bind.host || "127.0.0.1"}:${bind.port || 1984}`;
  $("#settingsBind").textContent = `${bind.host || "127.0.0.1"}:${bind.port || 1984}`;
  renderSiteStatus();
  renderPort443(data.port_443 || {});
  const trafficRows = data.stats_history || [];
  const latest = trafficRows[trafficRows.length - 1] || {};
  const previous = trafficRows[trafficRows.length - 2] || {};
  const elapsed = Math.max(1, (Number(latest.epoch) || 0) - (Number(previous.epoch) || 0));
  const latestProxy = Number(latest.proxy_bytes) || 0;
  const previousProxy = Number(previous.proxy_bytes) || 0;
  const currentDelta = Number(latest.proxy_delta) || (latestProxy >= previousProxy ? latestProxy - previousProxy : latestProxy);
  const currentRate = Math.max(0, currentDelta) / elapsed;
  const liveConnections = state.users.reduce((sum, user) => sum + (Number(user.traffic?.current_connections) || 0), 0);
  const activeIps = state.users.reduce((sum, user) => sum + (Number(user.traffic?.active_unique_ips) || 0), 0);
  $("#portPublicAddress").textContent = `${cfg.domain || cfg.mask_host || "сервер"}:${cfg.port || 443}`;
  $("#portCurrentRate").textContent = `${fmtBytes(currentRate)}/с`;
  $("#portNetworkDc").textContent = cfg.network_dc_count || 1;
  $("#portConnections").textContent = liveConnections;
  $("#portActiveIps").textContent = activeIps;
  $("#networkDcCount").value = cfg.network_dc_count || 1;
  $("#metricUsers").textContent = data.users_count ?? 0;
  $("#metricProxyTraffic").textContent = fmtBytes(stats.proxy_bytes);
  $("#metricProxyPackets").textContent = `${stats.proxy_pkts || 0} ${t("packets")}`;
  $("#metricSiteTraffic").textContent = fmtBytes(stats.site_bytes);
  $("#metricSitePackets").textContent = `${stats.site_pkts || 0} ${t("packets")}`;
  $("#cpuPercent").textContent = setGauge("#cpuGauge", system.cpu_percent);
  $("#cpuMeta").textContent = `${system.cpu_count || 0} CPU · load ${(system.load || [0])[0] || 0}`;
  $("#memoryPercent").textContent = setGauge("#memoryGauge", memory.percent);
  $("#memoryMeta").textContent = `${fmtBytes(memory.used)} / ${fmtBytes(memory.total)}`;
  $("#diskPercent").textContent = setGauge("#diskGauge", disk.percent);
  $("#diskMeta").textContent = `${fmtBytes(disk.used)} / ${fmtBytes(disk.total)}`;
  $("#systemUptime").textContent = fmtDuration(system.uptime_seconds);
  $("#systemHostname").textContent = system.hostname || "--";
  $("#lastRefresh").textContent = fmtDate(Math.floor(Date.now() / 1000));
  renderServices(data.services || {});
  renderRuntime();
  renderOperationsSummary();
  renderStats();
  renderBackups(data.backups || []);
  renderConfig();
}

function statsPayload() {
  if (state.stats) return state.stats;
  return {
    current: state.overview?.stats_current || {},
    history: state.overview?.stats_history || [],
    status: state.overview?.stats_status || {},
    summary_rows: [],
  };
}

function updateTrafficControls() {
  $$("[data-traffic-range]").forEach((btn) => {
    btn.classList.toggle("active", btn.dataset.trafficRange === state.trafficRange);
  });
  $$("[data-traffic-view]").forEach((btn) => {
    btn.classList.toggle("active", btn.dataset.trafficView === state.trafficView);
  });
  $$("[data-traffic-metric]").forEach((btn) => {
    btn.classList.toggle("active", btn.dataset.trafficMetric === state.trafficMetric);
  });
  $("#trafficSmooth").checked = state.trafficSmooth;
  $("#trafficProxySeries").checked = state.trafficProxySeries;
  $("#trafficSiteSeries").checked = state.trafficSiteSeries;
  $("#trafficHideIdle").checked = state.trafficHideIdle;
  $("#trafficTableOrder").value = state.trafficTableOrder;
}

function updateUserTrafficControls() {
  $$("[data-user-traffic-range]").forEach((btn) => {
    btn.classList.toggle("active", btn.dataset.userTrafficRange === state.userTrafficRange);
  });
  $$("[data-user-traffic-view]").forEach((btn) => {
    btn.classList.toggle("active", btn.dataset.userTrafficView === state.userTrafficView);
  });
  $$("[data-user-traffic-metric]").forEach((btn) => {
    btn.classList.toggle("active", btn.dataset.userTrafficMetric === state.userTrafficMetric);
  });
  $("#userTrafficSmooth").checked = state.userTrafficSmooth;
}

function trafficRangeLabel(range) {
  const labels = {
    "15m": t("range15m"),
    "1h": t("range1h"),
    "6h": "6 часов",
    "24h": t("range24h"),
    "7d": "7 дней",
    month: t("rangeMonth"),
  };
  return labels[range] || range;
}

function rangeSeconds(range) {
  return {
    "15m": 15 * 60,
    "1h": 60 * 60,
    "6h": 6 * 60 * 60,
    "24h": 24 * 60 * 60,
    "7d": 7 * 24 * 60 * 60,
    month: 30 * 24 * 60 * 60,
  }[range] || 60 * 60;
}

function filterTrafficRows(rows, range = state.trafficRange) {
  if (!Array.isArray(rows) || !rows.length) return [];
  const deduped = new Map();
  rows.forEach((row) => {
    const epoch = Number(row.epoch) || 0;
    if (epoch > 0) deduped.set(epoch, { ...row, epoch });
  });
  const ordered = Array.from(deduped.values()).sort((a, b) => a.epoch - b.epoch);
  if (!ordered.length) return [];
  const latest = ordered[ordered.length - 1].epoch;
  const cutoff = latest - rangeSeconds(range);
  return ordered.filter((row) => row.epoch >= cutoff);
}

function bucketTrafficRows(rows) {
  const filtered = filterTrafficRows(rows);
  if (filtered.length <= 140) return filtered;
  const chunk = Math.ceil(filtered.length / 120);
  const buckets = [];
  for (let i = 0; i < filtered.length; i += chunk) {
    const slice = filtered.slice(i, i + chunk);
    const last = slice[slice.length - 1];
    buckets.push({
      epoch: last.epoch,
      proxy_delta: slice.reduce((sum, item) => sum + (Number(item.proxy_delta) || 0), 0),
      site_delta: slice.reduce((sum, item) => sum + (Number(item.site_delta) || 0), 0),
      proxy_bytes: last.proxy_bytes,
      site_bytes: last.site_bytes,
    });
  }
  return buckets;
}

function fallbackTrafficSummaries(rows) {
  return trafficRanges.map((range) => {
    const windowRows = filterTrafficRows(rows, range);
    if (!windowRows.length) {
      return { range, points: 0, proxy_delta: 0, site_delta: 0, proxy_total: 0, site_total: 0 };
    }
    const first = windowRows[0];
    const last = windowRows[windowRows.length - 1];
    return {
      range,
      points: windowRows.length,
      proxy_delta: windowRows.reduce((sum, item) => sum + Math.max(0, Number(item.proxy_delta) || 0), 0),
      site_delta: windowRows.reduce((sum, item) => sum + Math.max(0, Number(item.site_delta) || 0), 0),
      proxy_total: Number(last.proxy_bytes) || 0,
      site_total: Number(last.site_bytes) || 0,
    };
  });
}

function renderTrafficLoading() {
  $("#trafficChart").classList.toggle("is-hidden", state.trafficView !== "chart");
  $("#trafficTableWrap").classList.toggle("is-hidden", state.trafficView !== "table");
  $("#trafficChart").innerHTML = `<div class="empty-chart"><strong>${escapeHtml(t("loading"))}</strong></div>`;
  $("#historyTable").innerHTML = `<tr><td colspan="5" class="empty-cell">${escapeHtml(t("loading"))}</td></tr>`;
}

function renderStats() {
  const payload = statsPayload();
  const status = payload.status || {};
  const stats = payload.current || {};
  const historyRows = payload.history || [];
  const summaryRows = payload.summary_rows?.length ? payload.summary_rows : fallbackTrafficSummaries(historyRows);
  $("#statsHealth").className = `status-pill health-${escapeAttr(status.health || "unknown")}`;
  $("#statsHealth").textContent = healthLabel(status.health);
  $("#collectorState").textContent = status.service ? statusLabel(status.service) : "--";
  $("#lastStatsPoint").textContent = status.last_ts ? fmtDate(status.last_ts) : t("never");
  $("#historyRows").textContent = status.history_rows ?? historyRows.length;
  $("#repairStatsBtn").classList.toggle("attention", status.health !== "ok");
  $("#collectStatsBtn").disabled = status.service === "not_installed";
  $("#metricProxyTraffic").textContent = fmtBytes(stats.proxy_bytes);
  $("#metricSiteTraffic").textContent = fmtBytes(stats.site_bytes);
  updateTrafficControls();
  if (state.trafficLoading) {
    renderTrafficLoading();
    return;
  }
  $("#trafficChart").classList.toggle("is-hidden", state.trafficView !== "chart");
  $("#trafficTableWrap").classList.toggle("is-hidden", state.trafficView !== "table");
  renderTrafficInsights(historyRows);
  drawTrafficChart(historyRows);
  renderHistoryTable(summaryRows);
}

function renderTrafficInsights(rows) {
  const points = filterTrafficRows(rows);
  const proxy = points.reduce((sum, item) => sum + Math.max(0, Number(item.proxy_delta) || 0), 0);
  const site = points.reduce((sum, item) => sum + Math.max(0, Number(item.site_delta) || 0), 0);
  const rates = points.map((item, index) => {
    const before = points[Math.max(0, index - 1)];
    const after = points[Math.min(points.length - 1, index + 1)];
    const seconds = Math.max(1, index ? Number(item.epoch) - Number(before.epoch) : Number(after.epoch) - Number(item.epoch));
    return Math.max(0, Number(item.proxy_delta) || 0) / seconds;
  });
  const peakRate = Math.max(0, ...rates);
  const currentRate = rates[rates.length - 1] || 0;
  const html = `
    <article class="chart-insight series-proxy"><span>${escapeHtml(t("chartProxyPeriod"))}</span><strong>${escapeHtml(fmtBytes(proxy))}</strong><small>${escapeHtml(trafficRangeLabel(state.trafficRange))}</small></article>
    <article class="chart-insight series-site"><span>${escapeHtml(t("chartSitePeriod"))}</span><strong>${escapeHtml(fmtBytes(site))}</strong><small>${escapeHtml(trafficRangeLabel(state.trafficRange))}</small></article>
    <article class="chart-insight"><span>Сейчас</span><strong>${escapeHtml(`${fmtBytes(currentRate)}/с`)}</strong><small>последний интервал</small></article>
    <article class="chart-insight"><span>Пиковая скорость</span><strong>${escapeHtml(`${fmtBytes(peakRate)}/с`)}</strong><small>${escapeHtml(`${points.length} точек`)}</small></article>`;
  stableHtml($("#trafficInsights"), html, JSON.stringify([state.trafficRange, proxy, site, currentRate, peakRate, points.length]));
}

function drawTrafficChart(rows) {
  const el = $("#trafficChart");
  let rawPoints = bucketTrafficRows(rows);
  if (state.trafficHideIdle) {
    rawPoints = rawPoints.filter((point) => (Number(point.proxy_delta) || 0) > 0 || (Number(point.site_delta) || 0) > 0);
  }
  const points = rawPoints.map((point, index) => {
    const previous = rawPoints[Math.max(0, index - 1)];
    const next = rawPoints[Math.min(rawPoints.length - 1, index + 1)];
    const seconds = Math.max(1, index
      ? (Number(point.epoch) || 0) - (Number(previous.epoch) || 0)
      : (Number(next.epoch) || 0) - (Number(point.epoch) || 0));
    if (state.trafficMetric === "total") {
      return { ...point, proxy_value: Number(point.proxy_bytes) || 0, site_value: Number(point.site_bytes) || 0 };
    }
    if (state.trafficMetric === "rate") {
      return { ...point, proxy_value: (Number(point.proxy_delta) || 0) / seconds, site_value: (Number(point.site_delta) || 0) / seconds };
    }
    return { ...point, proxy_value: Number(point.proxy_delta) || 0, site_value: Number(point.site_delta) || 0 };
  });
  const proxyColor = getComputedStyle(document.documentElement).getPropertyValue("--blue").trim() || "#2563eb";
  const siteColor = getComputedStyle(document.documentElement).getPropertyValue("--green").trim() || "#0f9f6e";
  if (points.length < 2) {
    stableHtml(el, `<div class="empty-chart">
      <strong>${escapeHtml(points.length ? t("noTrafficForRange") : t("noHistory"))}</strong>
      <span>${escapeHtml(state.overview?.stats_status?.health === "ok" ? t("statsOk") : t("statsMissing"))}</span>
    </div>`, JSON.stringify(["empty", points.length, state.trafficRange]));
    return;
  }
  const width = 900;
  const height = 300;
  const pad = { l: 54, r: 22, t: 24, b: 42 };
  const max = Math.max(1, ...points.map((p) => Math.max(
    state.trafficProxySeries ? p.proxy_value || 0 : 0,
    state.trafficSiteSeries ? p.site_value || 0 : 0,
  )));
  const plotW = width - pad.l - pad.r;
  const plotH = height - pad.t - pad.b;
  const firstEpoch = Number(points[0].epoch) || 0;
  const lastEpoch = Number(points[points.length - 1].epoch) || firstEpoch + 1;
  const toX = (i) => pad.l + plotW * ((Number(points[i].epoch) || firstEpoch) - firstEpoch) / Math.max(1, lastEpoch - firstEpoch);
  const toY = (v) => pad.t + plotH - ((v || 0) / max) * plotH;
  const pathFor = (key) => {
    if (state.trafficSmooth) return smoothSvgPath(points, key, toX, toY);
    return points.map((point, index) => `${index ? "L" : "M"}${toX(index).toFixed(1)},${toY(point[key]).toFixed(1)}`).join(" ");
  };
  const grid = Array.from({ length: 5 }, (_, i) => {
    const y = pad.t + (plotH / 4) * i;
    return `<line x1="${pad.l}" y1="${y}" x2="${width - pad.r}" y2="${y}"></line>`;
  }).join("");
  const valueLabel = (value) => `${fmtBytes(value)}${state.trafficMetric === "rate" ? "/с" : ""}`;
  const metricLabel = state.trafficMetric === "rate" ? "скорость" : (state.trafficMetric === "total" ? "накопительный итог" : "за интервал");
  const axis = `макс. ${valueLabel(max)} · ${metricLabel}`;
  const firstTime = compactTime(points[0].epoch);
  const lastTime = compactTime(points[points.length - 1].epoch);
  const lastProxy = points[points.length - 1].proxy_value || 0;
  const lastSite = points[points.length - 1].site_value || 0;
  const pointMarkers = points.map((point, index) => {
    const label = `${fmtDate(point.epoch)} · прокси ${valueLabel(point.proxy_value)} · сайт ${valueLabel(point.site_value)}`;
    return `${state.trafficProxySeries ? `<circle class="chart-point" cx="${toX(index)}" cy="${toY(point.proxy_value)}" r="4" fill="${proxyColor}"><title>${escapeHtml(label)}</title></circle>` : ""}
      ${state.trafficSiteSeries ? `<circle class="chart-point" cx="${toX(index)}" cy="${toY(point.site_value)}" r="4" fill="${siteColor}"><title>${escapeHtml(label)}</title></circle>` : ""}`;
  }).join("");
  const html = `<svg viewBox="0 0 ${width} ${height}" role="img" aria-label="${escapeAttr(t("ariaTrafficHistory"))}">
    <defs>
      <linearGradient id="proxyGradient" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0%" stop-color="${proxyColor}" stop-opacity=".28"></stop>
        <stop offset="100%" stop-color="${proxyColor}" stop-opacity="0"></stop>
      </linearGradient>
      <linearGradient id="siteGradient" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0%" stop-color="${siteColor}" stop-opacity=".2"></stop>
        <stop offset="100%" stop-color="${siteColor}" stop-opacity="0"></stop>
      </linearGradient>
    </defs>
    <g class="grid">${grid}</g>
    ${state.trafficProxySeries ? `<path class="area proxy-area" style="fill:url(#proxyGradient)" d="${pathFor("proxy_value")} L${toX(points.length - 1)},${height - pad.b} L${toX(0)},${height - pad.b} Z"></path><path class="line proxy-line" pathLength="1" d="${pathFor("proxy_value")}"></path><circle class="last-point" cx="${toX(points.length - 1)}" cy="${toY(lastProxy)}" r="5" fill="${proxyColor}"></circle>` : ""}
    ${state.trafficSiteSeries ? `<path class="area site-area" style="fill:url(#siteGradient)" d="${pathFor("site_value")} L${toX(points.length - 1)},${height - pad.b} L${toX(0)},${height - pad.b} Z"></path><path class="line site-line" pathLength="1" d="${pathFor("site_value")}"></path><circle class="last-point" cx="${toX(points.length - 1)}" cy="${toY(lastSite)}" r="5" fill="${siteColor}"></circle>` : ""}
    ${pointMarkers}
    <text x="${pad.l}" y="17" class="axis">${escapeHtml(axis)}</text>
    <text x="${pad.l - 8}" y="${pad.t + 4}" text-anchor="end" class="axis-value">${escapeHtml(valueLabel(max))}</text>
    <text x="${pad.l - 8}" y="${pad.t + plotH / 2 + 4}" text-anchor="end" class="axis-value">${escapeHtml(valueLabel(max / 2))}</text>
    <text x="${pad.l}" y="${height - pad.b + 18}" class="axis-time">${escapeHtml(firstTime)}</text>
    <text x="${width - pad.r}" y="${height - pad.b + 18}" text-anchor="end" class="axis-time">${escapeHtml(lastTime)}</text>
  </svg>`;
  stableHtml(el, html, JSON.stringify([state.trafficRange, state.theme, state.trafficMetric, state.trafficSmooth, state.trafficProxySeries, state.trafficSiteSeries, state.trafficHideIdle, points]));
}

function renderHistoryTable(rows) {
  if (!rows.length) {
    $("#historyTable").innerHTML = `<tr><td colspan="5" class="empty-cell">${escapeHtml(t("noHistory"))}</td></tr>`;
    return;
  }
  const ordered = state.trafficTableOrder === "oldest" ? rows.slice() : rows.slice().reverse();
  $("#historyTable").innerHTML = ordered.map((row) => `
    <tr>
      <td data-label="${escapeAttr(t("tablePeriod"))}"><strong>${escapeHtml(trafficRangeLabel(row.range))}</strong><small>${escapeHtml(row.points ? `${row.points} ${t("historyRows").toLowerCase()}` : t("noTrafficForRange"))}</small></td>
      <td data-label="${escapeAttr(t("tableProxyDelta"))}">${escapeHtml(fmtBytes(row.proxy_delta))}</td>
      <td data-label="${escapeAttr(t("tableSiteDelta"))}">${escapeHtml(fmtBytes(row.site_delta))}</td>
      <td data-label="${escapeAttr(t("tableProxyTotal"))}">${escapeHtml(fmtBytes(row.proxy_total))}</td>
      <td data-label="${escapeAttr(t("tableSiteTotal"))}">${escapeHtml(fmtBytes(row.site_total))}</td>
    </tr>
  `).join("");
}

function ensureUserTrafficSelection() {
  if (state.userTrafficUser && state.users.some((user) => user.name === state.userTrafficUser)) return;
  state.userTrafficUser = state.users[0]?.name || "";
}

async function selectUserTraffic(name, options = {}) {
  const next = String(name || "");
  if (!next || !state.users.some((user) => user.name === next)) return;
  const changed = state.userTrafficUser !== next;
  state.userTrafficUser = next;
  if (changed) {
    state.userTraffic = null;
  }
  renderUsers();
  renderUserTraffic();
  if (options.scroll) {
    $("#userTrafficPanel")?.scrollIntoView({ behavior: "smooth", block: "start" });
  }
  try {
    await refreshUserTraffic({ showLoading: true });
  } catch (err) {
    toast(err.message);
  }
}

function userTrafficRows() {
  return state.userTraffic?.history || [];
}

function bucketUserTrafficRows(rows) {
  const filtered = filterTrafficRows(rows, state.userTrafficRange);
  if (filtered.length <= 140) return filtered;
  const chunk = Math.ceil(filtered.length / 120);
  const buckets = [];
  for (let i = 0; i < filtered.length; i += chunk) {
    const slice = filtered.slice(i, i + chunk);
    const last = slice[slice.length - 1];
    buckets.push({
      epoch: last.epoch,
      total_delta: slice.reduce((sum, item) => sum + (Number(item.total_delta) || 0), 0),
      total_octets: last.total_octets,
      current_connections: last.current_connections,
      active_unique_ips: last.active_unique_ips,
    });
  }
  return buckets;
}

function fallbackUserTrafficSummaries(rows) {
  return trafficRanges.map((range) => {
    const windowRows = filterTrafficRows(rows, range);
    if (!windowRows.length) {
      return { range, points: 0, total_delta: 0, total_octets: 0 };
    }
    const last = windowRows[windowRows.length - 1];
    return {
      range,
      points: windowRows.length,
      total_delta: windowRows.reduce((sum, item) => sum + Math.max(0, Number(item.total_delta) || 0), 0),
      total_octets: Number(last.total_octets) || 0,
    };
  });
}

function renderUserTrafficLoading() {
  $("#userTrafficChart").classList.toggle("is-hidden", state.userTrafficView !== "chart");
  $("#userTrafficTableWrap").classList.toggle("is-hidden", state.userTrafficView !== "table");
  $("#userTrafficChart").innerHTML = `<div class="empty-chart"><strong>${escapeHtml(t("loading"))}</strong></div>`;
  $("#userTrafficTable").innerHTML = `<tr><td colspan="3" class="empty-cell">${escapeHtml(t("loading"))}</td></tr>`;
}

function drawUserTrafficChart(rows) {
  const el = $("#userTrafficChart");
  const rawPoints = bucketUserTrafficRows(rows);
  const points = rawPoints.map((point, index) => {
    const previous = rawPoints[Math.max(0, index - 1)];
    const next = rawPoints[Math.min(rawPoints.length - 1, index + 1)];
    const seconds = Math.max(1, index
      ? Number(point.epoch) - Number(previous.epoch)
      : Number(next.epoch) - Number(point.epoch));
    const value = state.userTrafficMetric === "total"
      ? Number(point.total_octets) || 0
      : (state.userTrafficMetric === "rate"
        ? (Number(point.total_delta) || 0) / seconds
        : Number(point.total_delta) || 0);
    return { ...point, chart_value: value };
  });
  const color = getComputedStyle(document.documentElement).getPropertyValue("--blue").trim() || "#2563eb";
  if (points.length < 2) {
    stableHtml(el, `<div class="empty-chart">
      <strong>${escapeHtml(state.userTrafficUser ? t("noTrafficForRange") : t("selectUserTraffic"))}</strong>
      <span>${escapeHtml(state.userTraffic?.status?.runtime_ok ? t("statsOk") : t("trafficRuntimeUnavailable"))}</span>
    </div>`, JSON.stringify(["empty", state.userTrafficUser, state.userTrafficRange]));
    return;
  }
  const width = 900;
  const height = 260;
  const pad = { l: 54, r: 22, t: 24, b: 42 };
  const max = Math.max(1, ...points.map((p) => Number(p.chart_value) || 0));
  const plotW = width - pad.l - pad.r;
  const plotH = height - pad.t - pad.b;
  const firstEpoch = Number(points[0].epoch) || 0;
  const lastEpoch = Number(points[points.length - 1].epoch) || firstEpoch + 1;
  const toX = (i) => pad.l + plotW * ((Number(points[i].epoch) || firstEpoch) - firstEpoch) / Math.max(1, lastEpoch - firstEpoch);
  const toY = (v) => pad.t + plotH - ((v || 0) / max) * plotH;
  const path = state.userTrafficSmooth
    ? smoothSvgPath(points, "chart_value", toX, toY)
    : points.map((point, index) => `${index ? "L" : "M"}${toX(index).toFixed(1)},${toY(point.chart_value).toFixed(1)}`).join(" ");
  const grid = Array.from({ length: 5 }, (_, i) => {
    const y = pad.t + (plotH / 4) * i;
    return `<line x1="${pad.l}" y1="${y}" x2="${width - pad.r}" y2="${y}"></line>`;
  }).join("");
  const suffix = state.userTrafficMetric === "rate" ? "/с" : "";
  const modeLabel = state.userTrafficMetric === "rate" ? "скорость" : (state.userTrafficMetric === "total" ? "накопительный итог" : "за интервал");
  const axis = `макс. ${fmtBytes(max)}${suffix} · ${modeLabel}`;
  const firstTime = compactTime(points[0].epoch);
  const lastTime = compactTime(points[points.length - 1].epoch);
  const lastValue = Number(points[points.length - 1].chart_value) || 0;
  const html = `<svg viewBox="0 0 ${width} ${height}" role="img" aria-label="${escapeAttr(t("ariaTrafficHistory"))}">
    <defs>
      <linearGradient id="userGradient" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0%" stop-color="${color}" stop-opacity=".28"></stop>
        <stop offset="100%" stop-color="${color}" stop-opacity="0"></stop>
      </linearGradient>
    </defs>
    <g class="grid">${grid}</g>
    <path class="area proxy-area" style="fill:url(#userGradient)" d="${path} L${toX(points.length - 1)},${height - pad.b} L${toX(0)},${height - pad.b} Z"></path>
    <path class="line proxy-line" pathLength="1" d="${path}"></path>
    <circle class="last-point" cx="${toX(points.length - 1)}" cy="${toY(lastValue)}" r="5" fill="${color}"></circle>
    <text x="${pad.l}" y="17" class="axis">${escapeHtml(axis)}</text>
    <text x="${pad.l - 8}" y="${pad.t + 4}" text-anchor="end" class="axis-value">${escapeHtml(`${fmtBytes(max)}${suffix}`)}</text>
    <text x="${pad.l - 8}" y="${pad.t + plotH / 2 + 4}" text-anchor="end" class="axis-value">${escapeHtml(`${fmtBytes(max / 2)}${suffix}`)}</text>
    <text x="${pad.l}" y="${height - pad.b + 18}" class="axis-time">${escapeHtml(firstTime)}</text>
    <text x="${width - pad.r}" y="${height - pad.b + 18}" text-anchor="end" class="axis-time">${escapeHtml(lastTime)}</text>
  </svg>`;
  stableHtml(el, html, JSON.stringify([state.userTrafficUser, state.userTrafficRange, state.userTrafficMetric, state.userTrafficSmooth, state.theme, points]));
}

function renderUserTrafficInsights(rows) {
  const points = filterTrafficRows(rows, state.userTrafficRange);
  const period = points.reduce((sum, item) => sum + Math.max(0, Number(item.total_delta) || 0), 0);
  const peak = Math.max(0, ...points.map((item) => Number(item.total_delta) || 0));
  const current = state.userTraffic?.current || {};
  const html = `
    <article class="chart-insight"><span>${escapeHtml(t("chartPeriodTraffic"))}</span><strong>${escapeHtml(fmtBytes(period))}</strong><small>${escapeHtml(trafficRangeLabel(state.userTrafficRange))}</small></article>
    <article class="chart-insight"><span>${escapeHtml(t("chartPeak"))}</span><strong>${escapeHtml(fmtBytes(peak))}</strong><small>${escapeHtml(t("chartExplanation"))}</small></article>
    <article class="chart-insight"><span>${escapeHtml(t("onlineNow"))}</span><strong>${escapeHtml(`${current.current_connections ?? 0} / ${current.active_unique_ips ?? 0} IP`)}</strong><small>${escapeHtml(t("currentConnections"))}</small></article>`;
  stableHtml($("#userTrafficInsights"), html, JSON.stringify([state.userTrafficUser, state.userTrafficRange, period, peak, current.current_connections, current.active_unique_ips]));
}

function renderUserTrafficTable(rows) {
  if (!rows.length) {
    $("#userTrafficTable").innerHTML = `<tr><td colspan="3" class="empty-cell">${escapeHtml(t("noHistory"))}</td></tr>`;
    return;
  }
  $("#userTrafficTable").innerHTML = rows.map((row) => `
    <tr>
      <td data-label="${escapeAttr(t("tablePeriod"))}"><strong>${escapeHtml(trafficRangeLabel(row.range))}</strong><small>${escapeHtml(row.points ? `${row.points} ${t("historyRows").toLowerCase()}` : t("noTrafficForRange"))}</small></td>
      <td data-label="${escapeAttr(t("tableTrafficDelta"))}">${escapeHtml(fmtBytes(row.total_delta))}</td>
      <td data-label="${escapeAttr(t("tableTrafficTotal"))}">${escapeHtml(fmtBytes(row.total_octets))}</td>
    </tr>
  `).join("");
}

function renderUserTraffic() {
  updateUserTrafficControls();
  if (!state.userTrafficUser) {
    $("#userTrafficTitle").textContent = t("userTrafficTitle");
    $("#userTrafficHealth").className = "status-pill health-unknown";
    $("#userTrafficHealth").textContent = "--";
    $("#userTrafficTotal").textContent = "--";
    $("#userTrafficConnections").textContent = "--";
    $("#userTrafficIps").textContent = "--";
    stableHtml($("#userTrafficInsights"), "", "empty");
    $("#userTrafficChart").innerHTML = `<div class="empty-chart"><strong>${escapeHtml(t("selectUserTraffic"))}</strong></div>`;
    $("#userTrafficTable").innerHTML = `<tr><td colspan="3" class="empty-cell">${escapeHtml(t("selectUserTraffic"))}</td></tr>`;
    return;
  }
  $("#userTrafficTitle").textContent = `${t("userTrafficTitle")}: ${state.userTrafficUser}`;
  if (state.userTrafficLoading) {
    renderUserTrafficLoading();
    return;
  }
  const payload = state.userTraffic || {};
  const current = payload.current || {};
  const rows = userTrafficRows();
  const last = rows[rows.length - 1] || {};
  const total = Number(current.total_octets) || Number(last.total_octets) || 0;
  $("#userTrafficHealth").className = `status-pill ${current.enabled === false ? "health-stopped" : (current.ok ? "health-ok" : "health-stale")}`;
  $("#userTrafficHealth").textContent = current.enabled === false ? t("disabled") : (current.ok ? t("healthOk") : t("trafficRuntimeUnavailable"));
  $("#userTrafficTotal").textContent = fmtBytes(total);
  $("#userTrafficConnections").textContent = current.current_connections ?? last.current_connections ?? 0;
  $("#userTrafficIps").textContent = current.active_unique_ips ?? last.active_unique_ips ?? 0;
  $("#userTrafficChart").classList.toggle("is-hidden", state.userTrafficView !== "chart");
  $("#userTrafficTableWrap").classList.toggle("is-hidden", state.userTrafficView !== "table");
  renderUserTrafficInsights(rows);
  drawUserTrafficChart(rows);
  renderUserTrafficTable(payload.summary_rows?.length ? payload.summary_rows : fallbackUserTrafficSummaries(rows));
}

function renderUsers() {
  const container = $("#usersTable");
  const needle = state.userSearch.trim().toLowerCase();
  const enabledCount = state.users.filter((user) => user.enabled).length;
  const onlineCount = state.users.filter((user) => Number(user.traffic?.current_connections) > 0).length;
  const totalConnections = state.users.reduce((sum, user) => sum + (Number(user.traffic?.current_connections) || 0), 0);
  const totalTraffic = state.users.reduce((sum, user) => sum + (Number(user.traffic?.total_octets) || 0), 0);
  const dashboard = [
    [t("enabled"), `${enabledCount} / ${state.users.length}`, enabledCount === state.users.length ? "good" : "warn"],
    [t("onlineNow"), onlineCount, onlineCount ? "good" : ""],
    [t("activeConnections"), totalConnections, totalConnections ? "good" : ""],
    [t("totalTraffic"), fmtBytes(totalTraffic), ""],
  ];
  stableHtml($("#keysDashboard"), dashboard.map(([label, value, level]) => `
    <article class="summary-tile ${escapeAttr(level)}"><span>${escapeHtml(label)}</span><strong>${escapeHtml(value)}</strong></article>
  `).join(""), JSON.stringify(dashboard));
  $$("[data-user-filter]").forEach((button) => button.classList.toggle("active", button.dataset.userFilter === state.userFilter));
  const visibleUsers = state.users.filter((user) => {
    if (needle && !user.name.toLowerCase().includes(needle)) return false;
    if (state.userFilter === "enabled" && !user.enabled) return false;
    if (state.userFilter === "disabled" && user.enabled) return false;
    if (state.userFilter === "online" && !(Number(user.traffic?.current_connections) > 0)) return false;
    return true;
  });
  $("#keysSummary").textContent = `${visibleUsers.length} / ${state.users.length} ${t("keysShown")}`;
  if (!visibleUsers.length) {
    stableHtml(container, `<div class="empty empty-cell">${escapeHtml(t("noKeys"))}</div>`, `empty:${state.userFilter}:${needle}`);
    return;
  }
  const html = visibleUsers.map((user) => {
    const pending = state.pendingUsers.has(user.name);
    const selected = user.name === state.userTrafficUser;
    const traffic = user.traffic || {};
    const trafficTotal = Number(traffic.total_octets) ? fmtBytes(traffic.total_octets) : "--";
    const activeIps = Number(traffic.active_unique_ips) || 0;
    const connections = Number(traffic.current_connections) || 0;
    const maxUniqueIps = Number.isFinite(Number(user.max_unique_ips)) ? Math.max(0, Number(user.max_unique_ips)) : 0;
    const revealed = state.revealedUsers.has(user.name);
    return `
    <article class="key-card ${user.enabled ? "" : "disabled-row"} ${pending ? "pending-row" : ""} ${selected ? "selected-row" : ""}" data-select-user-traffic="${escapeAttr(user.name)}" aria-selected="${selected ? "true" : "false"}">
      <div class="key-card-user">
        <button class="key-name-button" type="button" data-user-traffic="${escapeAttr(user.name)}">
          <strong>${escapeHtml(user.name)}</strong>${user.main ? ` <small>${escapeHtml(t("main"))}</small>` : ""}
        </button>
        <div class="status-control">
          <label class="switch" title="${escapeAttr(user.main ? t("main") : (user.enabled ? t("disableKey") : t("enableKey")))}">
            <input type="checkbox" data-toggle-user="${escapeAttr(user.name)}" ${user.enabled ? "checked" : ""} ${user.main || pending ? "disabled" : ""}>
            <span></span>
          </label>
          <strong class="${user.enabled ? "state-on" : "state-off"}">${escapeHtml(pending ? t("applying") : (user.enabled ? t("enabled") : t("disabled")))}</strong>
        </div>
        <button class="soft" data-user-traffic="${escapeAttr(user.name)}">${escapeHtml(t("openStats"))}</button>
      </div>
      <div class="key-card-traffic">
        <span class="field-label">${escapeHtml(t("onlineNow"))}</span>
        <div class="key-live-grid">
          <div><span>${escapeHtml(t("currentConnections"))}</span><strong>${escapeHtml(connections)}</strong></div>
          <div><span>${escapeHtml(t("activeIps"))}</span><strong>${escapeHtml(activeIps)}</strong></div>
          <div><span>${escapeHtml(t("totalTraffic"))}</span><strong>${escapeHtml(trafficTotal)}</strong></div>
        </div>
        <form class="ip-limit-control" data-ip-limit-form="${escapeAttr(user.name)}" title="${escapeAttr(t("ipLimitHint"))}">
          <span>${escapeHtml(t("ipLimit"))}</span>
          <input type="number" min="0" max="1000000" step="1" value="${escapeAttr(maxUniqueIps)}" data-ip-limit-input="${escapeAttr(user.name)}" aria-label="${escapeAttr(t("ipLimit"))}: ${escapeAttr(user.name)}">
          <button class="soft" type="submit" data-ip-limit-save="${escapeAttr(user.name)}">${escapeHtml(t("saveIpLimit"))}</button>
        </form>
      </div>
      <div class="key-card-access">
        <span class="field-label">${escapeHtml(t("tableSecret"))}</span>
        <div class="key-secret-line">
          <code title="${escapeAttr(revealed ? user.secret : t("showSecret"))}">${escapeHtml(revealed ? user.secret : "••••••••••••••••••••••••••••••••")}</code>
          <button class="soft" data-reveal-user="${escapeAttr(user.name)}">${escapeHtml(revealed ? t("hideSecret") : t("showSecret"))}</button>
        </div>
        <div class="key-quick-actions">
          <button class="soft" data-copy="${escapeAttr(user.link)}" ${user.enabled ? "" : "disabled"}>${escapeHtml(t("copyLink"))}</button>
          <button class="soft" data-user-qr="${escapeAttr(user.name)}">${escapeHtml(t("showQr"))}</button>
          <button class="soft" data-copy="${escapeAttr(user.secret)}">${escapeHtml(t("copySecret"))}</button>
          <button class="danger" data-delete="${escapeAttr(user.name)}" ${user.main ? "disabled" : ""}>${escapeHtml(t("delete"))}</button>
        </div>
      </div>
    </article>
  `; }).join("");
  const signature = JSON.stringify([visibleUsers, state.userTrafficUser, state.userFilter, needle, [...state.pendingUsers], [...state.revealedUsers]]);
  stableHtml(container, html, signature);
}

function renderBackups(backups) {
  const box = $("#backupsList");
  renderBackupSchedule();
  const schedule = state.backupSchedule || state.overview?.backup_schedule || {};
  const totalSize = backups.reduce((sum, item) => sum + (Number(item.size) || 0), 0);
  const next = schedule.frequency === "off" ? t("scheduleOff") : (fmtSystemdTime(schedule.next) || schedule.calendar || "--");
  const summary = [
    [t("backupLast"), backups[0] ? fmtDate(backups[0].mtime) : t("never")],
    [t("backupCount"), backups.length],
    [t("backupSize"), fmtBytes(totalSize)],
    [t("backupNext"), next],
  ];
  stableHtml($("#backupDashboard"), summary.map(([label, value]) => `
    <article class="summary-tile"><span>${escapeHtml(label)}</span><strong>${escapeHtml(value)}</strong></article>
  `).join(""), JSON.stringify(summary));
  if (!backups.length) {
    stableHtml(box, `<div class="empty">${escapeHtml(t("noBackups"))}</div>`, "empty");
    return;
  }
  const html = backups.map((item, index) => `
    <div class="backup-item">
      <div>
        <div class="backup-item-name">
          <strong>${escapeHtml(fmtDate(item.mtime))}</strong>
          ${index === 0 ? `<span class="backup-badge">${escapeHtml(t("backupReady"))}</span>` : ""}
        </div>
        <span title="${escapeAttr(item.name)}">${escapeHtml(item.name)}</span>
      </div>
      <div class="backup-actions">
        <span>${escapeHtml(fmtBytes(item.size))}${item.encrypted ? ` · ${escapeHtml(t("encrypted"))}` : ""}</span>
        <button class="soft" data-restore-backup="${escapeAttr(item.name)}" ${item.restorable === false ? "disabled" : ""} title="${escapeAttr(item.restorable === false ? t("encryptedRestoreCli") : t("restoreBackup"))}">${escapeHtml(t("restoreBackup"))}</button>
      </div>
    </div>
  `).join("");
  stableHtml(box, html, JSON.stringify(backups));
}

function renderBackupSchedule() {
  const schedule = state.backupSchedule || state.overview?.backup_schedule || { frequency: "off" };
  const frequency = schedule.frequency || "off";
  $$("[data-backup-schedule]").forEach((btn) => {
    btn.classList.toggle("active", btn.dataset.backupSchedule === frequency);
  });
  const next = fmtSystemdTime(schedule.next);
  $("#backupScheduleMeta").textContent = frequency === "off"
    ? t("scheduleDisabled")
    : t("scheduleNext").replace("{value}", next || (schedule.calendar || "--"));
}

function renderEvents() {
  const box = $("#events");
  if (!state.events.length) {
    box.innerHTML = `<div class="empty">${escapeHtml(t("noEvents"))}</div>`;
    return;
  }
  box.innerHTML = state.events.map((item) => `
    <div class="event">
      <strong>${escapeHtml(item.title)}</strong>
      <small title="${escapeAttr(item.detail || "")}">${escapeHtml(item.detail || item.time.toLocaleTimeString())}</small>
    </div>
  `).join("");
}

function renderConfig() {
  const cfg = state.overview?.config || {};
  const site = state.overview?.site_status || {};
  const mode = modePresentation(cfg.mode);
  const items = [
    [t("configMode"), mode.label],
    [t("configDomain"), cfg.domain || cfg.mask_host || "--"],
    [t("configSiteStatus"), siteStatusText(site)],
    [t("configTemplate"), cfg.template_id || cfg.template || "--"],
    [t("configVersion"), state.overview?.version || "--"],
    [t("bindAddress"), `${state.overview?.admin_bind?.host || "127.0.0.1"}:${state.overview?.admin_bind?.port || 1984}`],
  ];
  $("#configList").innerHTML = items.map(([label, value]) => `
    <div>
      <span>${escapeHtml(label)}</span>
      <strong>${escapeHtml(value)}</strong>
    </div>
  `).join("");
}

function renderSiteSettings() {
  const data = state.siteSettings;
  if (!data) return;
  if (!state.selectedSitePreset) state.selectedSitePreset = data.preset || data.presets?.[0]?.id || "";
  $("#sitePresetCards").innerHTML = (data.presets || []).map((preset) => `
    <button type="button" class="site-preset-card ${preset.id === state.selectedSitePreset ? "active" : ""}"
      data-site-preset="${escapeAttr(preset.id)}" ${preset.available ? "" : "disabled"}>
      <strong>${escapeHtml(preset.name)}</strong>
      <span>${escapeHtml(preset.description)}</span>
    </button>
  `).join("");
  const enabledKeys = (data.keys || []).filter((item) => item.enabled);
  $("#siteKey").innerHTML = enabledKeys.map((item) => `
    <option value="${escapeAttr(item.name)}" ${item.name === data.key ? "selected" : ""}>${escapeHtml(item.name)}</option>
  `).join("");
  $("#customSiteKey").innerHTML = enabledKeys.map((item) => `
    <option value="${escapeAttr(item.name)}" ${item.name === data.key ? "selected" : ""}>${escapeHtml(item.name)}</option>
  `).join("");
}

async function saveSiteSettings() {
  const button = $("#siteSettingsForm button[type=submit]");
  button.disabled = true;
  try {
    state.siteSettings = await api("/api/site/settings", {
      method: "POST",
      body: JSON.stringify({ preset: state.selectedSitePreset, key: $("#siteKey").value }),
    });
    renderSiteSettings();
    toast("Сайт опубликован");
    await refreshAll({ silent: true });
  } finally {
    button.disabled = false;
  }
}

async function saveCustomSite() {
  const file = $("#customSiteFile").files?.[0];
  if (!file) throw new Error("Выберите HTML-файл");
  if (file.size > 512 * 1024) throw new Error("HTML больше 512 КБ");
  const source = await file.text();
  const button = $("#customSiteForm button[type=submit]");
  button.disabled = true;
  try {
    state.siteSettings = await api("/api/site/custom", {
      method: "POST",
      body: JSON.stringify({ html: source, key: $("#customSiteKey").value }),
    });
    state.selectedSitePreset = "custom";
    renderSiteSettings();
    $("#customSiteFile").value = "";
    $("#customSiteDrop").classList.remove("is-ready");
    $("#customSiteFileName").textContent = "или перетащите его сюда · до 512 КБ";
    toast("Свой сайт опубликован");
    await refreshAll({ silent: true });
  } finally {
    button.disabled = false;
  }
}

async function saveGeneralSettings() {
  await api("/api/settings/general", {
    method: "POST",
    body: JSON.stringify({ network_dc_count: Number($("#networkDcCount").value) || 1 }),
  });
  toast("Настройки сохранены");
  await refreshAll({ silent: true });
}

async function refreshAll(options = {}) {
  if (state.refreshingAll) return;
  state.refreshingAll = true;
  const btn = $("#refreshBtn");
  if (!options.silent) btn.disabled = true;
  try {
    const [overview, users, siteSettings] = await Promise.all([
      api("/api/overview"),
      api("/api/users"),
      api("/api/site/settings"),
    ]);
    state.overview = overview;
    state.backupSchedule = state.overview.backup_schedule || state.backupSchedule;
    updateLanguageFromOverview(state.overview);
    state.users = users;
    state.siteSettings = siteSettings;
    ensureUserTrafficSelection();
    if (!state.stats) {
      state.stats = {
        current: state.overview.stats_current || {},
        history: state.overview.stats_history || [],
        status: state.overview.stats_status || {},
        summary_rows: [],
      };
    } else {
      state.stats = {
        ...state.stats,
        current: state.overview.stats_current || state.stats.current || {},
        status: state.overview.stats_status || state.stats.status || {},
      };
    }
    renderOverview();
    renderUsers();
    renderSiteSettings();
    if (state.page === "traffic") {
      await refreshStats();
    } else if (state.page === "keys") {
      ensureUserTrafficSelection();
      await refreshUserTraffic();
    }
  } catch (err) {
    if (!options.silent) toast(err.message);
  } finally {
    if (!options.silent) btn.disabled = false;
    state.refreshingAll = false;
    updateAutoRefreshToggle();
  }
}

async function refreshUsers() {
  state.users = await api("/api/users");
  renderUsers();
}

async function refreshStats(options = {}) {
  if (options.showLoading) {
    state.trafficLoading = true;
    renderStats();
  }
  try {
    const data = await api(`/api/stats?range=${encodeURIComponent(state.trafficRange)}`);
    state.stats = data;
    return data;
  } finally {
    state.trafficLoading = false;
    renderStats();
  }
}

async function refreshUserTraffic(options = {}) {
  ensureUserTrafficSelection();
  if (!state.userTrafficUser) {
    renderUserTraffic();
    return null;
  }
  if (options.showLoading) {
    state.userTrafficLoading = true;
    renderUserTraffic();
  }
  try {
    const data = await api(`/api/users/${encodeURIComponent(state.userTrafficUser)}/traffic?range=${encodeURIComponent(state.userTrafficRange)}`);
    state.userTraffic = data;
    return data;
  } finally {
    state.userTrafficLoading = false;
    renderUserTraffic();
  }
}

async function changeTrafficRange(range) {
  const next = trafficRanges.includes(range) ? range : "1h";
  if (next === state.trafficRange && state.stats?.range === next) return;
  const previous = state.trafficRange;
  state.trafficRange = next;
  try {
    await refreshStats({ showLoading: true });
  } catch (err) {
    state.trafficRange = previous;
    state.trafficLoading = false;
    renderStats();
    toast(err.message);
  }
}

async function changeUserTrafficRange(range) {
  const next = trafficRanges.includes(range) ? range : "1h";
  if (next === state.userTrafficRange && state.userTraffic?.range === next) return;
  const previous = state.userTrafficRange;
  state.userTrafficRange = next;
  try {
    await refreshUserTraffic({ showLoading: true });
  } catch (err) {
    state.userTrafficRange = previous;
    state.userTrafficLoading = false;
    renderUserTraffic();
    toast(err.message);
  }
}

async function addUser(name) {
  const data = await api("/api/users", {
    method: "POST",
    body: JSON.stringify({ name }),
  });
  addEvent(t("keyCreated"), data.name);
  toast(t("keyCreated"));
  await refreshAll();
}

async function deleteUser(name) {
  await api(`/api/users/${encodeURIComponent(name)}`, { method: "DELETE" });
  addEvent(t("keyDeleted"), name);
  toast(t("keyDeleted"));
  await refreshAll();
}

async function setUserEnabled(name, enabled) {
  const previousUsers = state.users.map((user) => ({ ...user }));
  state.pendingUsers.add(name);
  state.users = state.users.map((user) => user.name === name ? { ...user, enabled } : user);
  renderUsers();
  try {
    const data = await api(`/api/users/${encodeURIComponent(name)}/enabled`, {
      method: "POST",
      body: JSON.stringify({ enabled }),
    });
    state.users = state.users.map((user) => user.name === name ? { ...user, enabled: data.enabled } : user);
    const message = data.enabled ? t("keyEnabled") : t("keyDisabled");
    addEvent(message, name);
    toast(t("changesApplyInBackground"));
    try {
      await refreshUsers();
    } catch (refreshErr) {
      toast(refreshErr.message);
    }
    setTimeout(() => refreshAll().catch((err) => toast(err.message)), 1400);
  } catch (err) {
    state.users = previousUsers;
    toast(err.message);
  } finally {
    state.pendingUsers.delete(name);
    renderUsers();
  }
}

async function setUserMaxUniqueIps(name, value) {
  const limit = Number.parseInt(value, 10);
  if (!Number.isFinite(limit) || limit < 0 || limit > 1000000) {
    toast(t("ipLimitHint"));
    return;
  }
  const form = $$("[data-ip-limit-form]").find((item) => item.dataset.ipLimitForm === name);
  const controls = form ? Array.from(form.querySelectorAll("input, button")) : [];
  controls.forEach((control) => { control.disabled = true; });
  try {
    const data = await api(`/api/users/${encodeURIComponent(name)}/max-ips`, {
      method: "POST",
      body: JSON.stringify({ max_unique_ips: limit }),
    });
    state.users = state.users.map((user) => user.name === name ? { ...user, max_unique_ips: data.max_unique_ips } : user);
    renderUsers();
    addEvent(t("ipLimitSaved"), `${name}: ${data.max_unique_ips}`);
    toast(t("changesApplyInBackground"));
    setTimeout(() => refreshAll().catch((err) => toast(err.message)), 1400);
  } catch (err) {
    toast(err.message);
  } finally {
    controls.forEach((control) => { control.disabled = false; });
  }
}

async function createBackup() {
  const btn = $("#createBackupBtn");
  btn.disabled = true;
  try {
    const data = await api("/api/backups", { method: "POST", body: "{}" });
    addEvent(t("backupCreated"), data.path || "");
    toast(t("backupCreated"));
    await refreshAll();
  } catch (err) {
    toast(err.message);
  } finally {
    btn.disabled = false;
  }
}

async function setBackupSchedule(frequency) {
  $$("[data-backup-schedule]").forEach((btn) => { btn.disabled = true; });
  try {
    const data = await api("/api/backups/schedule", {
      method: "POST",
      body: JSON.stringify({ frequency }),
    });
    state.backupSchedule = data.schedule || data;
    renderBackupSchedule();
    renderBackups(state.overview?.backups || []);
    addEvent(t("scheduleSaved"), frequency);
    toast(t("scheduleSaved"));
  } catch (err) {
    toast(err.message);
  } finally {
    $$("[data-backup-schedule]").forEach((btn) => { btn.disabled = false; });
  }
}

async function restoreBackup(name) {
  const data = await api("/api/backups/restore", {
    method: "POST",
    body: JSON.stringify({ name }),
  });
  addEvent(t("backupRestoreStarted"), data.name || name);
  toast(t("backupRestoreStarted"));
  setTimeout(() => refreshAll().catch((err) => toast(err.message)), 4000);
}

function showUserQr(name) {
  const user = state.users.find((item) => item.name === name);
  if (!user) {
    toast(t("qrUnavailable"));
    return;
  }
  state.qrLink = user.link || "";
  $("#qrTitle").textContent = `${t("qrTitle")} · ${user.name}`;
  $("#qrMeta").textContent = user.link || "";
  const img = $("#qrImage");
  img.alt = `${user.name} Telegram proxy QR`;
  img.onerror = () => {
    img.removeAttribute("src");
    toast(t("qrUnavailable"));
  };
  img.src = `/api/users/${encodeURIComponent(user.name)}/qr?ts=${Date.now()}`;
  $("#qrModal").hidden = false;
}

function explainLogLine(raw, service) {
  const match = String(raw).match(/^(\d{4}-\d{2}-\d{2}T\S+)\s+\S+\s+[^:]+:\s?(.*)$/);
  const timestamp = match?.[1] || "";
  const message = (match?.[2] || raw).trim();
  const lower = message.toLowerCase();
  if (!message) return null;
  if (/rpc handshake ok|writer restored/.test(lower)) {
    return { level: "good", icon: "✓", title: "Связь с Telegram восстановлена", explanation: "telemt успешно подключился к одному из промежуточных серверов Telegram.", timestamp, raw };
  }
  if (/initializing me pool/.test(lower)) {
    return { level: "", icon: "↻", title: "Подготовка соединений Telegram", explanation: "telemt создаёт резервный пул подключений к инфраструктуре Telegram.", timestamp, raw };
  }
  if (/key derivation parameters/.test(lower)) {
    return { level: "good", icon: "🔒", title: "Защищённый канал согласован", explanation: "Стороны обменялись параметрами шифрования. Это штатный этап подключения.", timestamp, raw };
  }
  if (/socket closed by peer on idle writer/.test(lower)) {
    return { level: "", icon: "i", title: "Неактивное соединение закрыто", explanation: "Telegram закрыл простаивающий канал; telemt автоматически создаст новый при необходимости.", timestamp, raw };
  }
  if (/upstream failed after retries|no healthy upstreams|pool is not ready|all me servers .* failed|marked unhealthy/.test(lower)) {
    return { level: "warn", icon: "!", title: "Канал Telegram временно недоступен", explanation: "Один или несколько upstream-серверов не ответили. telemt продолжает автоматические повторы и переключение на другой адрес.", timestamp, raw };
  }
  if (/error|failed|fatal|panic|traceback|permission denied|address already in use/.test(lower)) {
    return { level: "error", icon: "!", title: "Ошибка службы", explanation: "Служба сообщила об ошибке. Раскройте исходную строку — там будет техническая причина.", timestamp, raw };
  }
  if (/warning|warn|timeout|timed out|connection reset|broken pipe/.test(lower)) {
    const network = /connection reset|broken pipe/.test(lower);
    return { level: "warn", icon: "•", title: network ? "Соединение прервано клиентом" : "Предупреждение", explanation: network ? "Клиент закрыл соединение раньше завершения обмена. Единичные события обычно не требуют действий." : "Работа продолжается, но служба отметила потенциальную проблему.", timestamp, raw };
  }
  if (/"(GET|POST|PUT|DELETE|PATCH) [^"]+ HTTP\/[^"]+" (2\d\d|3\d\d)/.test(message)) {
    return { level: "good", icon: "↻", title: "Админка обновила данные", explanation: "Браузер успешно запросил свежие данные у локальной админки.", timestamp, raw };
  }
  if (/started|listening|ready|success|active \(running\)/.test(lower)) {
    return { level: "good", icon: "✓", title: "Служба готова к работе", explanation: "Запуск завершён успешно, сервис принимает запросы.", timestamp, raw };
  }
  if (/stopped|stopping|shut down|shutdown/.test(lower)) {
    return { level: "warn", icon: "■", title: "Служба остановлена", explanation: "Процесс завершил работу или был перезапущен оператором/systemd.", timestamp, raw };
  }
  if (/no journal entries/.test(lower)) {
    return { level: "", icon: "i", title: "Записей пока нет", explanation: "Для выбранной службы systemd-журнал пуст.", timestamp, raw };
  }
  if (/traffic|stats|collect|snapshot/.test(lower)) {
    return { level: "good", icon: "↗", title: "Статистика обновлена", explanation: "Сборщик записал очередной снимок трафика.", timestamp, raw };
  }
  return { level: "", icon: "i", title: "Техническое сообщение", explanation: `${service}: обычная информационная запись. Подробности доступны ниже.`, timestamp, raw };
}

function renderLogsView() {
  $$("[data-log-view]").forEach((button) => button.classList.toggle("active", button.dataset.logView === state.logView));
  const rawBox = $("#logsBox");
  const humanBox = $("#humanLogs");
  rawBox.classList.toggle("is-hidden", state.logView !== "raw");
  humanBox.classList.toggle("is-hidden", state.logView !== "human");
  const payload = state.logsPayload;
  if (!payload) {
    if (state.logView === "human") stableHtml(humanBox, `<div class="empty">${escapeHtml(t("loading"))}</div>`, "loading");
    return;
  }
  const text = typeof payload === "string" ? payload : (payload.text || "");
  rawBox.textContent = text || t("logsNoData");
  const service = payload.service || $("#logService").value;
  const parsed = text.split("\n").map((line) => explainLogLine(line, service)).filter(Boolean).slice(-120).reverse();
  const grouped = [];
  const byMeaning = new Map();
  parsed.forEach((item) => {
    const key = `${item.level}|${item.title}|${item.explanation}`;
    let group = byMeaning.get(key);
    if (!group) {
      group = { ...item, count: 0, samples: [] };
      byMeaning.set(key, group);
      grouped.push(group);
    }
    group.count += 1;
    if (group.samples.length < 3) group.samples.push(item.raw);
  });
  const html = grouped.length ? grouped.map((item) => `
    <article class="human-log ${escapeAttr(item.level)}">
      <span class="human-log-icon" aria-hidden="true">${escapeHtml(item.icon)}</span>
      <div>
        <div class="human-log-head"><strong>${escapeHtml(item.title)}${item.count > 1 ? ` · ${item.count}` : ""}</strong><time>${escapeHtml(item.timestamp ? new Date(item.timestamp).toLocaleString("ru-RU") : "")}</time></div>
        <p>${escapeHtml(item.explanation)}</p>
        <details><summary>${escapeHtml(t("logRawDetails"))}</summary><code>${escapeHtml(item.samples.join("\n\n"))}</code></details>
      </div>
    </article>
  `).join("") : `<div class="empty">${escapeHtml(t("logNoEvents"))}</div>`;
  stableHtml(humanBox, html, JSON.stringify([service, text]));
}

async function loadLogs() {
  const service = $("#logService").value;
  const btn = $("#loadLogsBtn");
  btn.disabled = true;
  $("#logsMeta").textContent = "";
  state.logsPayload = null;
  renderLogsView();
  try {
    const payload = await api(`/api/logs?service=${encodeURIComponent(service)}`);
    if ($("#logService").value === service) {
      const structured = payload && typeof payload === "object";
      const text = typeof payload === "string" ? payload : (payload?.text || "");
      const lines = structured ? (payload.line_count ?? text.split("\n").filter(Boolean).length) : text.split("\n").filter(Boolean).length;
      const stateText = structured ? (payload.ok ? "OK" : `exit ${payload.exit_code ?? "?"}`) : "OK";
      $("#logsMeta").textContent = `${service} · ${lines} ${t("logsLines")} · ${stateText}`;
      state.logsPayload = structured ? payload : { service, ok: true, text };
      renderLogsView();
    }
  } catch (err) {
    $("#logsMeta").textContent = "";
    state.logsPayload = { service, ok: false, text: err.message };
    renderLogsView();
  } finally {
    btn.disabled = false;
  }
}

async function restartService(name) {
  await api(`/api/services/${encodeURIComponent(name)}/restart`, { method: "POST", body: "{}" });
  addEvent(t("serviceRestarted"), name);
  toast(`${name} ${t("serviceRestarted").toLowerCase()}`);
  await refreshAll();
}

async function repairStats() {
  const btn = $("#repairStatsBtn");
  btn.disabled = true;
  try {
    await api("/api/stats/repair", { method: "POST", body: "{}" });
    addEvent(t("statsRepaired"));
    toast(t("statsRepaired"));
    await refreshAll();
    await refreshStats();
  } catch (err) {
    toast(err.message);
  } finally {
    btn.disabled = false;
  }
}

async function collectStats() {
  const btn = $("#collectStatsBtn");
  btn.disabled = true;
  try {
    await api("/api/stats/collect", { method: "POST", body: "{}" });
    addEvent(t("statsCollected"));
    toast(t("statsCollected"));
    await refreshAll();
    await refreshStats();
  } catch (err) {
    toast(err.message);
  } finally {
    btn.disabled = false;
  }
}

async function copyText(value) {
  try {
    await navigator.clipboard.writeText(value);
    toast(t("copied"));
  } catch (_) {
    const area = document.createElement("textarea");
    area.value = value;
    area.setAttribute("readonly", "");
    area.style.position = "fixed";
    area.style.opacity = "0";
    document.body.appendChild(area);
    area.select();
    const ok = document.execCommand("copy");
    area.remove();
    toast(ok ? t("copied") : t("copyFailed"));
  }
}

document.addEventListener("click", async (eventObj) => {
  const jump = eventObj.target.closest("[data-dashboard-jump]");
  if (jump) {
    setPage(jump.dataset.dashboardJump);
    return;
  }
  const nav = eventObj.target.closest("[data-nav]");
  if (nav) {
    setPage(nav.dataset.nav);
    return;
  }

  const button = eventObj.target.closest("button");
  if (button) {
    if (button.id === "themeToggle") {
      setThemeMode(state.theme === "dark" ? "light" : "dark");
    } else if (button.dataset.themeMode) {
      setThemeMode(button.dataset.themeMode);
    } else if (button.dataset.refreshMs !== undefined) {
      const interval = Number(button.dataset.refreshMs);
      setAutoRefresh(interval > 0, interval || state.autoRefreshMs);
    } else if (button.id === "menuBtn") {
      $("#sidebar").classList.toggle("open");
    } else if (button.dataset.trafficRange) {
      changeTrafficRange(button.dataset.trafficRange);
    } else if (button.dataset.trafficView) {
      state.trafficView = button.dataset.trafficView === "table" ? "table" : "chart";
      renderStats();
    } else if (button.dataset.trafficMetric) {
      state.trafficMetric = ["rate", "delta", "total"].includes(button.dataset.trafficMetric) ? button.dataset.trafficMetric : "rate";
      renderStats();
    } else if (button.dataset.sitePreset) {
      state.selectedSitePreset = button.dataset.sitePreset;
      renderSiteSettings();
    } else if (button.dataset.userTraffic) {
      selectUserTraffic(button.dataset.userTraffic, { scroll: true });
    } else if (button.dataset.userQr) {
      showUserQr(button.dataset.userQr);
    } else if (button.dataset.userTrafficRange) {
      changeUserTrafficRange(button.dataset.userTrafficRange);
    } else if (button.dataset.userTrafficView) {
      state.userTrafficView = button.dataset.userTrafficView === "table" ? "table" : "chart";
      renderUserTraffic();
    } else if (button.dataset.userTrafficMetric) {
      state.userTrafficMetric = ["rate", "delta", "total"].includes(button.dataset.userTrafficMetric) ? button.dataset.userTrafficMetric : "rate";
      renderUserTraffic();
    } else if (button.dataset.userFilter) {
      state.userFilter = ["enabled", "disabled", "online"].includes(button.dataset.userFilter) ? button.dataset.userFilter : "all";
      renderUsers();
    } else if (button.dataset.revealUser) {
      if (state.revealedUsers.has(button.dataset.revealUser)) state.revealedUsers.delete(button.dataset.revealUser);
      else state.revealedUsers.add(button.dataset.revealUser);
      renderUsers();
    } else if (button.dataset.logView) {
      state.logView = button.dataset.logView === "raw" ? "raw" : "human";
      renderLogsView();
    } else if (button.dataset.backupSchedule) {
      setBackupSchedule(button.dataset.backupSchedule);
    } else if (button.dataset.restoreBackup) {
      const name = button.dataset.restoreBackup;
      if (confirm(`${t("confirmRestoreBackup")} ${name}?`)) restoreBackup(name).catch((err) => toast(err.message));
    } else if (button.dataset.copy) {
      await copyText(button.dataset.copy);
    } else if (button.dataset.delete) {
      const name = button.dataset.delete;
      if (confirm(`${t("confirmDelete")} ${name}?`)) deleteUser(name).catch((err) => toast(err.message));
    } else if (button.dataset.restart) {
      const name = button.dataset.restart;
      if (confirm(`${t("confirmRestart")} ${name}?`)) restartService(name).catch((err) => toast(err.message));
    }
    return;
  }

  if (eventObj.target.closest("input, select, textarea, label, form")) return;
  const row = eventObj.target.closest("[data-select-user-traffic]");
  if (!row) return;
  selectUserTraffic(row.dataset.selectUserTraffic, { scroll: true });
});

document.addEventListener("change", (eventObj) => {
  if (eventObj.target.id === "customSiteFile") {
    const file = eventObj.target.files?.[0];
    $("#customSiteDrop").classList.toggle("is-ready", Boolean(file));
    $("#customSiteFileName").textContent = file
      ? `${file.name} · ${fmtBytes(file.size)}`
      : "или перетащите его сюда · до 512 КБ";
    return;
  }
  if (eventObj.target.id === "trafficSmooth") {
    state.trafficSmooth = eventObj.target.checked;
    renderStats();
    return;
  }
  if (eventObj.target.id === "trafficProxySeries" || eventObj.target.id === "trafficSiteSeries") {
    state.trafficProxySeries = $("#trafficProxySeries").checked;
    state.trafficSiteSeries = $("#trafficSiteSeries").checked;
    if (!state.trafficProxySeries && !state.trafficSiteSeries) {
      state.trafficProxySeries = true;
      $("#trafficProxySeries").checked = true;
    }
    renderStats();
    return;
  }
  if (eventObj.target.id === "trafficHideIdle") {
    state.trafficHideIdle = eventObj.target.checked;
    renderStats();
    return;
  }
  if (eventObj.target.id === "trafficTableOrder") {
    state.trafficTableOrder = eventObj.target.value === "oldest" ? "oldest" : "newest";
    renderStats();
    return;
  }
  if (eventObj.target.id === "userTrafficSmooth") {
    state.userTrafficSmooth = eventObj.target.checked;
    renderUserTraffic();
    return;
  }
  const input = eventObj.target.closest("[data-toggle-user]");
  if (!input) return;
  input.disabled = true;
  setUserEnabled(input.dataset.toggleUser, input.checked).catch((err) => {
    input.checked = !input.checked;
    input.disabled = false;
    toast(err.message);
  });
});

document.addEventListener("keydown", (eventObj) => {
  const jump = eventObj.target.closest(".dashboard-link[data-dashboard-jump]");
  if (!jump || !["Enter", " "].includes(eventObj.key)) return;
  eventObj.preventDefault();
  setPage(jump.dataset.dashboardJump);
});

["dragenter", "dragover"].forEach((eventName) => {
  $("#customSiteDrop").addEventListener(eventName, (eventObj) => {
    eventObj.preventDefault();
    $("#customSiteDrop").classList.add("is-dragging");
  });
});
["dragleave", "drop"].forEach((eventName) => {
  $("#customSiteDrop").addEventListener(eventName, (eventObj) => {
    eventObj.preventDefault();
    $("#customSiteDrop").classList.remove("is-dragging");
  });
});
$("#customSiteDrop").addEventListener("drop", (eventObj) => {
  const file = eventObj.dataTransfer?.files?.[0];
  if (!file) return;
  const transfer = new DataTransfer();
  transfer.items.add(file);
  $("#customSiteFile").files = transfer.files;
  $("#customSiteFile").dispatchEvent(new Event("change", { bubbles: true }));
});

$("#addUserForm").addEventListener("submit", (eventObj) => {
  eventObj.preventDefault();
  const input = $("#userName");
  const name = input.value.trim();
  if (!/^[A-Za-z0-9_.-]{1,48}$/.test(name)) {
    toast(t("invalidUser"));
    return;
  }
  input.value = "";
  addUser(name).catch((err) => toast(err.message));
});
$("#generalSettingsForm").addEventListener("submit", (eventObj) => {
  eventObj.preventDefault();
  saveGeneralSettings().catch((err) => toast(err.message));
});
$("#siteSettingsForm").addEventListener("submit", (eventObj) => {
  eventObj.preventDefault();
  saveSiteSettings().catch((err) => toast(err.message));
});
$("#customSiteForm").addEventListener("submit", (eventObj) => {
  eventObj.preventDefault();
  saveCustomSite().catch((err) => toast(err.message));
});
$("#userSearch").addEventListener("input", (eventObj) => {
  state.userSearch = eventObj.target.value || "";
  renderUsers();
});

document.addEventListener("submit", (eventObj) => {
  const form = eventObj.target.closest("[data-ip-limit-form]");
  if (!form) return;
  eventObj.preventDefault();
  const input = form.querySelector("[data-ip-limit-input]");
  setUserMaxUniqueIps(form.dataset.ipLimitForm, input?.value || "0");
});

$("#refreshBtn").addEventListener("click", refreshAll);
$("#autoRefreshToggle").addEventListener("click", () => setAutoRefresh(!state.autoRefreshEnabled));
$("#qrClose").addEventListener("click", () => {
  $("#qrModal").hidden = true;
});
$("#qrCopyBtn").addEventListener("click", () => {
  if (state.qrLink) copyText(state.qrLink);
});
$("#createBackupBtn").addEventListener("click", createBackup);
$("#loadLogsBtn").addEventListener("click", loadLogs);
$("#logService").addEventListener("change", loadLogs);
$("#repairStatsBtn").addEventListener("click", repairStats);
$("#collectStatsBtn").addEventListener("click", collectStats);
window.addEventListener("hashchange", () => setPage((location.hash || "#dashboard").slice(1), false));

setPage((location.hash || "#dashboard").slice(1), false);
setThemeMode(state.themeMode);
renderEvents();
syncAutoRefreshTimer();
refreshAll();
loadLogs();
