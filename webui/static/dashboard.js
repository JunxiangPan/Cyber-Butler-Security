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
      setText("securityDetail", i18n.t("dash.security.detail", {
        action: actions[data.action] || actions.send,
        target,
        channel: channels[data.channel] || channels.qq,
        seconds: formatNumber(data.remaining_seconds || 0),
      }));
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
    setInterval(loadUsage, 60000);
    setInterval(loadPlugins, 30000);
    setInterval(loadBackups, 60000);
  };

  initialize();
})();
