(() => {
  const root = document.documentElement;
  const stored = localStorage.getItem("cb-theme");
  const preferred = window.matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark";
  root.dataset.theme = stored || preferred;

  document.getElementById("themeToggle")?.addEventListener("click", () => {
    root.dataset.theme = root.dataset.theme === "dark" ? "light" : "dark";
    localStorage.setItem("cb-theme", root.dataset.theme);
  });

  const i18n = window.CBI18n;
  if (!i18n) return;

  let csrf = "";
  let filePath = "";
  let lastExpiry = 0;
  let lastFileItem = null;
  let statusState = { key: "", text: "", vars: null, kind: "" };
  const tempHistory = { cpu: [], gpu: [] };
  const $ = (id) => document.getElementById(id);
  const account = $("accountEmail");
  const serviceList = $("serviceList");
  const pluginList = $("pluginList");
  const logView = $("logView");
  const chatText = $("chatText");
  const chatCount = $("chatCount");
  const chatStatus = $("chatStatus");
  const chatSend = $("chatSend");
  const chatLog = $("chatLog");

  const CODE_KEYS = {
    "chat.rate_limited": "chat.error.rate",
    "chat.failed": "chat.error.failed",
    "chat.empty": "chat.error.empty",
    "files.denied": "files.error.denied",
    "files.too_large": "files.error.tooLarge",
    "files.blocked": "files.error.blocked",
    "files.not_found": "files.error.notFound",
    "auth.rate_limited": "auth.error.rate",
    "auth.invalid_code": "auth.error.codeInvalid",
    "auth.csrf_invalid": "chat.error.notReady",
    "service.status_failed": "app.failed",
    "service.temps_failed": "app.failed",
    "service.plugins_failed": "app.failed",
    "service.logs_failed": "dash.log.failed",
    "service.usage_failed": "app.failed",
    "service.backups_failed": "app.failed",
  };

  const redirectIfUnauthorized = (response) => {
    if (response.status === 401) {
      window.location.replace("/");
      return true;
    }
    return false;
  };

  const getJson = async (url) => {
    const response = await fetch(url, { credentials: "same-origin", cache: "no-store" });
    if (redirectIfUnauthorized(response)) return null;
    return response.json().catch(() => ({}));
  };

  const setText = (id, value) => {
    const node = $(id);
    if (node) node.textContent = value;
  };

  const errorText = (data, fallbackKey) => {
    const mapped = data && data.code ? CODE_KEYS[data.code] : "";
    if (mapped) return i18n.t(mapped);
    if (data && data.message) return data.message;
    return i18n.t(fallbackKey);
  };

  const formatNumber = (value) => i18n.number(value);
  const formatTime = (epochSeconds, opts = { hour: "2-digit", minute: "2-digit" }) => {
    if (!epochSeconds) return i18n.t("app.none");
    return i18n.formatDate(new Date(Number(epochSeconds) * 1000), opts);
  };
  const formatCost = (value) => {
    try {
      return new Intl.NumberFormat(i18n.locales[i18n.current], {
        minimumFractionDigits: 4,
        maximumFractionDigits: 4,
      }).format(Number(value));
    } catch {
      return Number(value).toFixed(4);
    }
  };

  const renderStatusState = () => {
    if (statusState.key) chatStatus.textContent = i18n.t(statusState.key, statusState.vars);
    else chatStatus.textContent = statusState.text || "";
    chatStatus.className = "chat-status" + (statusState.kind ? " " + statusState.kind : "");
  };

  const setChatStatus = (key, vars = null, kind = "") => {
    statusState = { key, text: "", vars, kind };
    renderStatusState();
  };

  const setChatError = (data, fallbackKey) => {
    const mapped = data && data.code ? CODE_KEYS[data.code] : "";
    if (mapped) {
      setChatStatus(mapped, null, "error");
    } else if (data && data.message) {
      statusState = { key: "", text: data.message, vars: null, kind: "error" };
      renderStatusState();
    } else {
      setChatStatus(fallbackKey, null, "error");
    }
  };

  const emailBanner = $("emailBanner");
  const emailSetupPanel = $("emailSetupPanel");
  const adminEmailInput = $("adminEmailInput");
  const emailSaveStatus = $("emailSaveStatus");

  const loadEmailStatus = async () => {
    if (!csrf) return;
    const data = await getJson("/api/config/email-status");
    if (!data || !data.ok) return;
    const physicalBanner = $("physicalBanner");
    if (physicalBanner) physicalBanner.hidden = data.physical_separated === true;
    if (data.email_ready) {
      if (emailBanner) emailBanner.hidden = true;
      return;
    }
    if (emailBanner) emailBanner.hidden = false;
    if (adminEmailInput && data.admin_email) adminEmailInput.value = data.admin_email;
    if (emailSaveStatus) {
      emailSaveStatus.textContent = data.email_secret_present
        ? "邮箱已填写，但 SMTP/邮件配置需要重新验证。"
        : "邮箱或 SMTP 配置缺失，请完成安装器配置。";
    }
  };

  const renderNetworkGuard = (data) => {
    const banner = $("wfpBanner");
    const title = $("wfpStatusTitle");
    const badge = $("wfpStatusBadge");
    const detail = $("wfpStatusDetail");
    const status = $("networkStatus");
    const guard = (data && data.guard) || {};
    const healthy = Boolean(data && data.ok && guard.healthy === true);
    if (banner) {
      banner.hidden = false;
      banner.classList.toggle("wfp-card-ok", healthy);
      banner.classList.toggle("wfp-card-warn", !healthy);
    }
    if (title) title.textContent = healthy ? "网络门卫在运行（只观察）" : "网络门卫没有运行";
    if (badge) badge.textContent = healthy ? "AUDIT · 只记录" : "未运行";
    if (detail) {
      if (healthy) {
        detail.textContent = "WFP Guard 正在运行，但 v1.6.2 只有 audit 模式：它会记录，不会强制断网。下面的白名单只是“访客名单”，不是已生效的防火墙。";
      } else {
        detail.textContent = guard.error
          ? ("WFP Guard 没有心跳或启动失败：" + guard.error + " 这不是病毒报警；但下面的白名单不会生效。")
          : "WFP Guard 没有心跳或尚未启动。这不是病毒报警；但下面的白名单只是草稿，不会生效。";
      }
    }
    if (status) {
      status.textContent = healthy ? "门卫运行中（audit，只记录）" : "门卫未运行：白名单未生效";
      status.style.color = healthy ? "#15803d" : "#b91c1c";
      status.style.fontWeight = "700";
    }
  };

  const loadNetworkGuard = async () => {
    if (!csrf) return;
    const data = await getJson("/api/security/network-policy");
    if (data && data.ok) renderNetworkGuard(data);
  };

  const loadNetworkPolicy = async () => {
    if (!csrf) return;
    const data = await getJson("/api/security/network-policy");
    if (!data || !data.ok) return;
    renderNetworkGuard(data);
    const policy = data.policy || {};
    const mode = $("networkMode");
    const domains = $("networkDomains");
    if (mode) mode.value = "audit";
    if (policy.mode === "enforce" && mode) mode.value = "audit";
    if (domains) {
      const names = (policy.allow || []).filter((x) => x.kind === "domain").map((x) => x.name);
      domains.value = names.join(String.fromCharCode(10));
    }
  };

  const saveNetworkPolicy = async () => {
    if (!csrf) return;
    const status = $("networkStatus");
    if (status) status.textContent = "保存中…";
    const response = await fetch("/api/security/network-policy", {
      method: "POST",
      credentials: "same-origin",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf },
      body: JSON.stringify({ mode: "audit", domains: $("networkDomains")?.value || "", block_unknown: true }),
    });
    const data = await response.json().catch(() => ({}));
    if (status) {
      status.textContent = response.ok && data.ok
        ? "已保存（audit 只记录；强制拦截未启用）"
        : (data.message || "保存失败，请重试");
      status.style.color = response.ok && data.ok ? "#15803d" : "#b91c1c";
    }
    if (response.ok && data.ok) await loadNetworkGuard();
  };

  const oneBotState = { token: "", revealed: false, timer: null };

  const maskOneBot = () => {
    const el = $("oneBotToken");
    if (el) el.textContent = oneBotState.token ? "••••••••••••" : "未生成";
    const btn = $("oneBotReveal");
    if (btn) btn.textContent = "显示";
    oneBotState.revealed = false;
    if (oneBotState.timer) { clearTimeout(oneBotState.timer); oneBotState.timer = null; }
  };

  const renderOneBot = (data) => {
    oneBotState.token = String((data && data.access_token) || "");
    const url = $("oneBotUrl");
    if (url && data && data.url) url.textContent = data.url;
    const file = $("oneBotTokenFile");
    if (file && data && data.token_file) file.textContent = data.token_file;
    const status = $("oneBotStatus");
    if (status) {
      status.textContent = oneBotState.token
        ? "凭据已加载。点“显示”查看，点“复制”复制到剪贴板。"
        : "还没有生成 OneBot Token；先在 AstrBot 中添加 OneBot 平台，或重新运行安装器。";
      status.style.color = oneBotState.token ? "#15803d" : "#b91c1c";
    }
    const copy = $("oneBotCopy");
    if (copy) copy.disabled = !oneBotState.token;
    maskOneBot();
  };

  const loadOneBotToken = async () => {
    if (!csrf) return;
    const data = await getJson("/api/security/onebot-token");
    if (data && data.ok) renderOneBot(data);
  };

  const revealOneBot = () => {
    const el = $("oneBotToken");
    const btn = $("oneBotReveal");
    if (!el || !oneBotState.token) return;
    oneBotState.revealed = !oneBotState.revealed;
    el.textContent = oneBotState.revealed ? oneBotState.token : "••••••••••••";
    if (btn) btn.textContent = oneBotState.revealed ? "隐藏" : "显示";
    if (oneBotState.timer) clearTimeout(oneBotState.timer);
    if (oneBotState.revealed) {
      oneBotState.timer = setTimeout(maskOneBot, 15000);
    }
  };

  const copyOneBot = async () => {
    const status = $("oneBotStatus");
    if (!oneBotState.token) return;
    try {
      await navigator.clipboard.writeText(oneBotState.token);
      if (status) { status.textContent = "已复制 Access Token。粘贴到 AstrBot OneBot 平台和 SnowLuma WebSocket 客户端。"; status.style.color = "#15803d"; }
    } catch {
      if (status) { status.textContent = "复制失败；点“显示”手动选择复制。"; status.style.color = "#b91c1c"; }
    }
  };

  const snowState = { password: "", revealed: false, timer: null };

  const maskSnow = () => {
    const el = $("snowLumaPassword");
    if (el) el.textContent = snowState.password ? "••••••••••••" : "未捕获";
    const btn = $("snowLumaReveal");
    if (btn) btn.textContent = "显示";
    snowState.revealed = false;
    if (snowState.timer) { clearTimeout(snowState.timer); snowState.timer = null; }
  };

  const renderSnow = (data) => {
    snowState.password = String((data && data.password) || "");
    const user = $("snowLumaUser");
    if (user) user.textContent = (data && data.username) || "—";
    const url = $("snowLumaUrl");
    if (url && data && data.url) url.textContent = data.url;
    const status = $("snowLumaStatus");
    if (status) {
      status.textContent = snowState.password
        ? "密码来自 SnowLuma 首次启动日志；登录后请尽快修改。"
        : "未捕获初始密码。请前往 http://127.0.0.1:5099 登录 SnowLuma 后台修改，或在 SnowLuma 配置目录手动重置。CBS 只读取日志，不越权写入。";
      status.style.color = snowState.password ? "#15803d" : "#b91c1c";
    }
    const copy = $("snowLumaCopy");
    if (copy) copy.disabled = !snowState.password;
    maskSnow();
  };

  const loadSnow = async () => {
    if (!csrf) return;
    const data = await getJson("/api/security/snowluma-credentials");
    if (data && data.ok) renderSnow(data);
  };

  const revealSnow = () => {
    const el = $("snowLumaPassword");
    const btn = $("snowLumaReveal");
    if (!el || !snowState.password) return;
    snowState.revealed = !snowState.revealed;
    el.textContent = snowState.revealed ? snowState.password : "••••••••••••";
    if (btn) btn.textContent = snowState.revealed ? "隐藏" : "显示";
    if (snowState.timer) clearTimeout(snowState.timer);
    if (snowState.revealed) snowState.timer = setTimeout(maskSnow, 15000);
  };

  const copySnow = async () => {
    const status = $("snowLumaStatus");
    if (!snowState.password) return;
    try {
      await navigator.clipboard.writeText(snowState.password);
      if (status) { status.textContent = "已复制 SnowLuma 初始密码。"; status.style.color = "#15803d"; }
    } catch {
      if (status) { status.textContent = "复制失败；点“显示”手动复制。"; status.style.color = "#b91c1c"; }
    }
  };

  const saveAdminEmail = async () => {
    if (!csrf || !adminEmailInput) return;
    if (emailSaveStatus) emailSaveStatus.textContent = "保存中… / Saving…";
    try {
      const response = await fetch("/api/config/admin-email", {
        method: "POST",
        credentials: "same-origin",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf },
        body: JSON.stringify({ email: adminEmailInput.value.trim() }),
      });
      const data = await response.json().catch(() => ({}));
      if (!response.ok || !data.ok) {
        if (emailSaveStatus) emailSaveStatus.textContent = data.message || "保存失败 / Save failed";
        return;
      }
      if (emailSaveStatus) emailSaveStatus.textContent = "已保存，请重新验证邮件审批。 / Saved.";
      await loadEmailStatus();
    } catch (error) {
      if (emailSaveStatus) emailSaveStatus.textContent = "保存失败 / Save failed";
    }
  };

  const renderSession = () => {
    setText("sessionExpiry", lastExpiry
      ? i18n.formatDate(new Date(lastExpiry * 1000), { dateStyle: "medium", timeStyle: "short" })
      : i18n.t("app.none"));
  };

  const loadStatus = async () => {
    if (!csrf) return;
    const data = await getJson("/api/status");
    if (!data || !data.ok) return;
    serviceList.replaceChildren();
    for (const [name, online] of Object.entries(data.services || {})) {
      const row = document.createElement("div");
      row.className = "service-row";
      const dot = document.createElement("span");
      dot.className = "service-dot" + (online ? " up" : " down");
      const label = document.createElement("span");
      label.textContent = name === "astrbot" ? "AstrBot" : name === "broker" ? "TOTP Broker" : "SnowLuma";
      const state = document.createElement("strong");
      state.textContent = i18n.t(online ? "dash.status.online" : "dash.status.offline");
      row.append(dot, label, state);
      serviceList.append(row);
    }
    setText("statusUpdated", formatTime(data.checked_at));
  };

  const drawChart = () => {
    const width = 600;
    const height = 170;
    const pad = 10;
    const plot = height - pad * 2;
    const count = Math.max(tempHistory.cpu.length, tempHistory.gpu.length, 2);
    const points = (values) => values.map((value, index) => {
      const x = pad + (index / (count - 1)) * (width - pad * 2);
      const y = height - pad - (Math.max(0, Math.min(100, value)) / 100) * plot;
      return `${x.toFixed(1)},${y.toFixed(1)}`;
    }).join(" ");
    $("cpuLine")?.setAttribute("points", points(tempHistory.cpu));
    $("gpuLine")?.setAttribute("points", points(tempHistory.gpu));
  };

  const loadTemps = async () => {
    if (!csrf) return;
    const data = await getJson("/api/temps");
    if (!data) return;
    if (!data.ok) {
      setText("tempSource", errorText(data, "dash.temp.unavailable"));
      return;
    }
    setText("cpuValue", data.cpu == null ? i18n.t("app.none") : `${formatNumber(Number(data.cpu).toFixed(1))} °C`);
    setText("gpuValue", data.gpu == null ? i18n.t("app.none") : `${formatNumber(Number(data.gpu).toFixed(1))} °C`);
    setText("vramValue", data.vram_used != null && data.vram_total != null
      ? `${formatNumber(Math.round(data.vram_used))} / ${formatNumber(Math.round(data.vram_total))} ${i18n.t("app.mb")}`
      : i18n.t("app.none"));
    if (data.cpu != null) { tempHistory.cpu.push(Number(data.cpu)); if (tempHistory.cpu.length > 30) tempHistory.cpu.shift(); }
    if (data.gpu != null) { tempHistory.gpu.push(Number(data.gpu)); if (tempHistory.gpu.length > 30) tempHistory.gpu.shift(); }
    drawChart();
    const source = data.source || i18n.t("dash.temp.sourceFallback");
    const load = data.gpu_load != null ? " · " + i18n.t("dash.temp.gpuLoad", { percent: formatNumber(Math.round(data.gpu_load)) }) : "";
    setText("tempSource", source + load);
    setText("tempsUpdated", i18n.formatDate(new Date(), { hour: "2-digit", minute: "2-digit" }));
  };

  const loadUsage = async () => {
    if (!csrf) return;
    const data = await getJson("/api/usage");
    if (!data) return;
    if (!data.ok) {
      setText("usageTokens", i18n.t("app.failed"));
      return;
    }
    setText("usageTokens", formatNumber(data.tokens || 0));
    setText("usageCalls", i18n.t("dash.card.tokenNote", { calls: formatNumber(data.calls || 0) }));
    if (data.pricing_configured) {
      setText("usageCost", "$" + formatCost(data.cost || 0));
      setText("usagePricingNote", i18n.t("dash.card.costNote"));
    } else {
      setText("usageCost", i18n.t("dash.card.costUnconfigured"));
      setText("usagePricingNote", i18n.t("dash.card.costUnpriced", { providers: (data.unpriced || []).join(" / ") }));
    }
    const providers = $("usageProviders");
    if (providers) {
      providers.replaceChildren();
      for (const item of data.providers || []) {
        const row = document.createElement("div");
        row.className = "usage-provider-row";
        row.textContent = i18n.t("dash.usage.provider", {
          provider: item.provider,
          tokens: formatNumber(item.tokens || 0),
        });
        providers.append(row);
      }
    }
  };

  const loadPlugins = async () => {
    if (!csrf) return;
    const data = await getJson("/api/astrbot/plugins");
    if (!data) return;
    pluginList.replaceChildren();
    if (!data.ok) {
      setText("pluginCount", i18n.t("app.failed"));
      return;
    }
    setText("pluginCount", i18n.t("dash.plugin.count", { count: formatNumber(data.count || 0) }));
    for (const item of (data.plugins || []).slice(0, 10)) {
      const li = document.createElement("li");
      const name = document.createElement("span");
      name.textContent = item.display_name || item.name || i18n.t("dash.plugin.unnamed");
      const status = document.createElement("em");
      status.className = item.activated ? "on" : "off";
      status.textContent = i18n.t(item.activated ? "dash.plugin.enabled" : "dash.plugin.disabled");
      li.append(name, status);
      pluginList.append(li);
    }
    if (!pluginList.children.length) {
      const li = document.createElement("li");
      li.className = "muted-line";
      li.textContent = i18n.t("dash.plugin.empty");
      pluginList.append(li);
    }
  };

  const loadLogs = async () => {
    if (!csrf) return;
    const name = $("logSelect")?.value || "astrbot";
    const data = await getJson(`/api/logs?name=${encodeURIComponent(name)}&lines=80`);
    if (!data) return;
    if (!data.ok) {
      logView.textContent = errorText(data, "dash.log.failed");
      return;
    }
    logView.textContent = data.available
      ? (data.lines.join("\n") || i18n.t("dash.log.empty"))
      : i18n.t("dash.log.missing");
    logView.scrollTop = logView.scrollHeight;
  };

  const loadBackups = async () => {
    if (!csrf) return;
    const data = await getJson("/api/backups");
    const list = $("backupList");
    if (!data || !data.ok || !list) {
      setText("backupTotal", i18n.t("app.failed"));
      return;
    }
    list.replaceChildren();
    setText("backupTotal", data.available ? i18n.formatSize(data.total) : i18n.t("dash.backup.noDir"));
    for (const item of (data.items || []).slice(0, 12)) {
      const li = document.createElement("li");
      const name = document.createElement("span");
      name.textContent = item.name;
      name.title = item.name;
      const meta = document.createElement("em");
      meta.textContent = `${i18n.t(item.kind === "directory" ? "dash.backup.dir" : "dash.backup.file")} · ${i18n.formatSize(item.size)}`;
      li.append(name, meta);
      list.append(li);
    }
    if (!list.children.length) {
      const li = document.createElement("li");
      li.className = "muted-line";
      li.textContent = i18n.t("dash.backup.empty");
      list.append(li);
    }
  };

  const undoTrash = async (id) => {
    if (!csrf) return;
    const response = await fetch("/api/security/trash/undo", {
      method: "POST",
      credentials: "same-origin",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf },
      body: JSON.stringify({ id }),
    });
    const data = await response.json().catch(() => ({}));
    setStatus("trashStatus", data.ok ? "撤回成功 / Restored" : (data.message || "撤回失败"));
    await loadTrash();
  };

  const loadTrash = async () => {
    if (!csrf) return;
    const panel = $("trashPanel");
    const list = $("trashList");
    if (!panel || !list) return;
    const data = await getJson("/api/security/trash");
    if (!data || !data.available || !(data.items || []).length) {
      panel.hidden = true;
      return;
    }
    panel.hidden = false;
    list.replaceChildren();
    for (const item of data.items) {
      const li = document.createElement("li");
      const label = document.createElement("span");
      label.textContent = item.original_path || item.id;
      const button = document.createElement("button");
      button.type = "button";
      button.className = "ghost-button";
      button.textContent = "撤回 / Undo";
      button.addEventListener("click", () => undoTrash(item.id));
      li.append(label, button);
      list.append(li);
    }
  };

  const loadSecurity = async () => {
    if (!csrf) return;
    const data = await getJson("/api/security/pending");
    const banner = $("securityBanner");
    if (!data || !banner) return;
    if (data.available && data.pending) {
      const actions = {
        delete: i18n.t("dash.security.action.delete"),
        overwrite: i18n.t("dash.security.action.overwrite"),
        send: i18n.t("dash.security.action.send"),
      };
      const channels = {
        email: i18n.t("dash.security.channel.email"),
        qq: i18n.t("dash.security.channel.qq"),
      };
      const target = data.target_name
        ? i18n.t("dash.security.target", { target: data.target_name })
        : "";
      const detail = i18n.t("dash.security.detail", {
        action: actions[data.action] || actions.send,
        target,
        channel: channels[data.channel] || channels.qq,
        seconds: formatNumber(data.remaining_seconds || 0),
      });
      const meta = data.target_size
        ? ` · ${i18n.formatSize(data.target_size)} · ${new Date(Number(data.target_mtime_ns) / 1e6).toLocaleString()}`
        : "";
      setText("securityDetail", detail + meta);
      banner.hidden = false;
    } else {
      banner.hidden = true;
    }
  };

  const appendBubble = (text) => {
    const empty = chatLog?.querySelector(".chat-empty");
    if (empty) empty.remove();
    const bubble = document.createElement("div");
    bubble.className = "chat-bubble user";
    bubble.textContent = text;
    chatLog?.append(bubble);
    if (chatLog) chatLog.scrollTop = chatLog.scrollHeight;
  };

  const sendChatMessage = async (message) => {
    const text = String(message || "").trim();
    if (!text) {
      setChatStatus("chat.error.empty", null, "error");
      return;
    }
    if (!csrf) {
      setChatStatus("chat.error.notReady", null, "error");
      return;
    }
    chatSend.disabled = true;
    setChatStatus("chat.sending");
    try {
      const response = await fetch("/api/chat/send", {
        method: "POST",
        credentials: "same-origin",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf },
        body: JSON.stringify({ message: text }),
      });
      const data = await response.json().catch(() => ({}));
      if (!response.ok || !data.ok) {
        setChatError(data, "chat.error.failed");
        return;
      }
      appendBubble(text);
      chatText.value = "";
      chatCount.textContent = i18n.t("chat.count", { count: formatNumber(0) });
      setChatStatus("chat.sent", null, "ok");
    } catch {
      setChatStatus("chat.error.network", null, "error");
    } finally {
      chatSend.disabled = false;
    }
  };

  const setTab = (name) => {
    document.querySelectorAll(".tab-button").forEach((button) => {
      button.classList.toggle("active", button.dataset.tab === name);
    });
    const monitor = $("monitorTab");
    const files = $("filesTab");
    if (monitor) monitor.hidden = name !== "monitor";
    if (files) files.hidden = name !== "files";
    if (name === "files") loadFiles(filePath);
  };

  const fileIsImage = (name) => /\.(png|jpe?g|gif|webp|bmp)$/i.test(name);
  const fileIsText = (name) => /\.(txt|md|log|csv|json|ya?ml|ini|conf|rst)$/i.test(name);

  const closeFileModal = () => {
    const modal = $("fileModal");
    if (modal) modal.hidden = true;
  };

  const fileErrorFromResponse = (response, data) => {
    if (data && data.code && CODE_KEYS[data.code]) return i18n.t(CODE_KEYS[data.code]);
    if (data && data.message) return data.message;
    if (response.status === 403) return i18n.t("files.error.denied");
    return i18n.t("files.error");
  };

  const openFile = async (item) => {
    const modal = $("fileModal");
    const title = $("fileTitle");
    const preview = $("filePreview");
    const meta = $("fileMeta");
    const link = $("fileDownload");
    if (!modal || !title || !preview || !meta || !link) return;
    lastFileItem = item;
    const url = `/api/files/download?path=${encodeURIComponent(item.path)}`;
    title.textContent = item.name;
    meta.textContent = `${i18n.formatSize(item.size)} · ${i18n.t("files.modified")}: ${i18n.formatDate(new Date(item.mtime * 1000), { dateStyle: "medium", timeStyle: "short" })}`;
    link.href = url + "&download=1";
    link.setAttribute("download", item.name);
    preview.replaceChildren();
    modal.hidden = false;

    if (fileIsImage(item.name)) {
      const img = document.createElement("img");
      img.src = url;
      img.alt = item.name;
      preview.append(img);
      return;
    }
    if (fileIsText(item.name)) {
      if (item.size > 1024 * 1024) {
        preview.textContent = i18n.t("files.preview.tooLarge");
        return;
      }
      try {
        const response = await fetch(url, { credentials: "same-origin", cache: "no-store" });
        if (redirectIfUnauthorized(response)) return;
        if (!response.ok) {
          const data = await response.json().catch(() => ({}));
          preview.textContent = fileErrorFromResponse(response, data);
          return;
        }
        const pre = document.createElement("pre");
        pre.textContent = await response.text();
        preview.append(pre);
      } catch {
        preview.textContent = i18n.t("files.preview.failed");
      }
      return;
    }
    preview.textContent = i18n.t("files.preview.unsupported");
  };

  const loadFiles = async (path) => {
    if (!csrf) return;
    const list = $("fileList");
    if (!list) return;
    filePath = path || "";
    setText("filePath", "/" + filePath);
    const response = await fetch(`/api/files/list?path=${encodeURIComponent(filePath)}`, {
      credentials: "same-origin",
      cache: "no-store",
    });
    if (redirectIfUnauthorized(response)) return;
    const data = await response.json().catch(() => ({}));
    list.replaceChildren();
    if (!response.ok || !data.ok) {
      const li = document.createElement("li");
      li.className = "muted-line";
      li.textContent = fileErrorFromResponse(response, data);
      list.append(li);
      return;
    }
    for (const item of data.entries || []) {
      const li = document.createElement("li");
      li.className = "file-row";
      const button = document.createElement("button");
      button.type = "button";
      button.className = "file-button";
      const icon = document.createElement("span");
      icon.className = "file-icon";
      icon.textContent = item.is_dir ? "▸" : "·";
      const name = document.createElement("span");
      name.className = "file-name";
      name.textContent = item.name;
      const size = document.createElement("span");
      size.className = "file-size";
      size.textContent = item.is_dir ? i18n.t("files.dir") : i18n.formatSize(item.size);
      button.append(icon, name, size);
      button.addEventListener("click", () => {
        if (item.is_dir) loadFiles(item.path);
        else openFile(item);
      });
      li.append(button);
      list.append(li);
    }
    if (!list.children.length) {
      const li = document.createElement("li");
      li.className = "muted-line";
      li.textContent = i18n.t("files.empty");
      list.append(li);
    }
  };

  const refreshAll = () => {
    renderSession();
    renderStatusState();
    loadStatus();
    loadTemps();
    loadUsage();
    loadPlugins();
    loadLogs();
    loadBackups();
    loadSecurity();
    loadTrash();
    if (!$("filesTab")?.hidden) loadFiles(filePath);
    if (lastFileItem && !$("fileModal")?.hidden) openFile(lastFileItem);
  };

  const initialize = async () => {
    await (window.CBI18nReady || i18n.init());
    window.addEventListener("cb:languagechange", refreshAll);
    $("logSelect")?.addEventListener("change", loadLogs);
    chatText?.addEventListener("input", () => {
      chatCount.textContent = i18n.t("chat.count", { count: formatNumber(chatText.value.length) });
    });
    chatSend?.addEventListener("click", () => sendChatMessage(chatText.value));
    document.querySelectorAll("[data-shortcut]").forEach((button) => {
      button.addEventListener("click", () => sendChatMessage(i18n.t(button.dataset.shortcut)));
    });
    document.querySelectorAll(".tab-button").forEach((button) => {
      button.addEventListener("click", () => setTab(button.dataset.tab));
    });
    $("fileRefresh")?.addEventListener("click", () => loadFiles(filePath));
    $("fileUp")?.addEventListener("click", () => {
      const parts = filePath.split("/").filter(Boolean);
      parts.pop();
      loadFiles(parts.join("/"));
    });
    $("fileClose")?.addEventListener("click", closeFileModal);
    $("fileModal")?.addEventListener("click", (event) => {
      if (event.target === $("fileModal")) closeFileModal();
    });

    $("emailSetupToggle")?.addEventListener("click", () => {
      if (emailSetupPanel) emailSetupPanel.hidden = !emailSetupPanel.hidden;
    });
    $("adminEmailSave")?.addEventListener("click", saveAdminEmail);
    $("networkSave")?.addEventListener("click", saveNetworkPolicy);
    $("networkRefresh")?.addEventListener("click", loadNetworkPolicy);
    $("oneBotReveal")?.addEventListener("click", revealOneBot);
    $("oneBotCopy")?.addEventListener("click", copyOneBot);
    $("snowLumaReveal")?.addEventListener("click", revealSnow);
    $("snowLumaCopy")?.addEventListener("click", copySnow);
    adminEmailInput?.addEventListener("keydown", (event) => {
      if (event.key === "Enter") { event.preventDefault(); saveAdminEmail(); }
    });

    fetch("/api/auth/me", { credentials: "same-origin", cache: "no-store" })
      .then((response) => {
        if (redirectIfUnauthorized(response)) return null;
        return response.json();
      })
      .then((data) => {
        if (!data || !data.ok) return;
        csrf = data.csrf;
        account.textContent = data.email;
        lastExpiry = data.expires_at || 0;
        renderSession();
        chatCount.textContent = i18n.t("chat.count", { count: formatNumber(0) });
        refreshAll();
        loadEmailStatus();
        loadNetworkPolicy();
        loadOneBotToken();
        loadSnow();
        setInterval(loadNetworkGuard, 10000);
      })
      .catch(() => {});

    document.getElementById("logoutButton")?.addEventListener("click", async () => {
      if (!csrf) {
        window.location.replace("/");
        return;
      }
      await fetch("/api/auth/logout", {
        method: "POST",
        credentials: "same-origin",
        headers: { "X-CSRF-Token": csrf },
      });
      window.location.replace("/");
    });

    setInterval(loadStatus, 5000);
    setInterval(loadTemps, 5000);
    setInterval(loadSecurity, 5000);
    setInterval(loadTrash, 5000);
    setInterval(loadUsage, 60000);
    setInterval(loadPlugins, 30000);
    setInterval(loadBackups, 60000);
    setInterval(loadEmailStatus, 10000);
  };

  initialize();
})();
