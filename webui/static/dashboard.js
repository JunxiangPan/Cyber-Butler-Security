(() => {
  const root = document.documentElement;
  const stored = localStorage.getItem("cb-theme");
  const preferred = window.matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark";
  root.dataset.theme = stored || preferred;

  document.getElementById("themeToggle")?.addEventListener("click", () => {
    root.dataset.theme = root.dataset.theme === "dark" ? "light" : "dark";
    localStorage.setItem("cb-theme", root.dataset.theme);
  });

  let csrf = "";
  let filePath = "";
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
  const tempHistory = { cpu: [], gpu: [] };

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

  const fmtTime = (epoch) => {
    if (!epoch) return "—";
    return new Date(epoch * 1000).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" });
  };

  const fmtSize = (bytes) => {
    if (bytes == null) return "—";
    if (bytes < 1024) return bytes + " B";
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB";
    return (bytes / 1024 / 1024).toFixed(1) + " MB";
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
      state.textContent = online ? "在线" : "离线";
      row.append(dot, label, state);
      serviceList.append(row);
    }
    setText("statusUpdated", fmtTime(data.checked_at));
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
    const cpuLine = $("cpuLine");
    const gpuLine = $("gpuLine");
    if (cpuLine) cpuLine.setAttribute("points", points(tempHistory.cpu));
    if (gpuLine) gpuLine.setAttribute("points", points(tempHistory.gpu));
  };

  const loadTemps = async () => {
    if (!csrf) return;
    const data = await getJson("/api/temps");
    if (!data) return;
    if (!data.ok) {
      setText("tempSource", data.error ? "监控暂不可用：" + data.error : "监控暂不可用");
      return;
    }
    setText("cpuValue", data.cpu == null ? "—" : data.cpu.toFixed(1) + " °C");
    setText("gpuValue", data.gpu == null ? "—" : data.gpu.toFixed(1) + " °C");
    setText("vramValue", data.vram_used != null && data.vram_total
      ? `${Math.round(data.vram_used)} / ${Math.round(data.vram_total)} MB` : "—");
    if (data.cpu != null) { tempHistory.cpu.push(Number(data.cpu)); if (tempHistory.cpu.length > 30) tempHistory.cpu.shift(); }
    if (data.gpu != null) { tempHistory.gpu.push(Number(data.gpu)); if (tempHistory.gpu.length > 30) tempHistory.gpu.shift(); }
    drawChart();
    setText("tempSource", (data.source || "传感器") + (data.gpu_load != null ? ` · GPU 占用 ${Math.round(data.gpu_load)}%` : ""));
    setText("tempsUpdated", new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }));
  };

  const loadUsage = async () => {
    if (!csrf) return;
    const data = await getJson("/api/usage");
    if (!data) return;
    if (!data.ok) {
      setText("usageTokens", "读取失败");
      return;
    }
    setText("usageTokens", Number(data.tokens || 0).toLocaleString());
    setText("usageCalls", Number(data.calls || 0).toLocaleString());
    setText("usageCost", data.pricing_configured ? "$" + Number(data.cost || 0).toFixed(4) : "未配置");
    setText("usagePricingNote", data.pricing_configured ? "按配置费率估算" : "未配置：" + (data.unpriced || []).join(" / "));
    const providers = $("usageProviders");
    if (providers) {
      providers.replaceChildren();
      for (const item of data.providers || []) {
        const row = document.createElement("div");
        row.className = "usage-provider-row";
        row.textContent = `${item.provider}: ${Number(item.tokens || 0).toLocaleString()} tokens`;
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
      setText("pluginCount", "读取失败");
      return;
    }
    setText("pluginCount", `${data.count} 个`);
    for (const item of (data.plugins || []).slice(0, 10)) {
      const li = document.createElement("li");
      const name = document.createElement("span");
      name.textContent = item.display_name || item.name || "未命名";
      const status = document.createElement("em");
      status.className = item.activated ? "on" : "off";
      status.textContent = item.activated ? "启用" : "停用";
      li.append(name, status);
      pluginList.append(li);
    }
    if (!pluginList.children.length) {
      const li = document.createElement("li");
      li.className = "muted-line";
      li.textContent = "没有插件数据";
      pluginList.append(li);
    }
  };

  const loadLogs = async () => {
    if (!csrf) return;
    const name = $("logSelect")?.value || "astrbot";
    const data = await getJson(`/api/logs?name=${encodeURIComponent(name)}&lines=80`);
    if (!data) return;
    if (!data.ok) {
      logView.textContent = "日志读取失败";
      return;
    }
    logView.textContent = data.available ? (data.lines.join("\n") || "（空）") : "日志文件不存在";
    logView.scrollTop = logView.scrollHeight;
  };

  const loadBackups = async () => {
    if (!csrf) return;
    const data = await getJson("/api/backups");
    const list = $("backupList");
    if (!data || !data.ok || !list) {
      setText("backupTotal", "读取失败");
      return;
    }
    list.replaceChildren();
    setText("backupTotal", data.available ? fmtSize(data.total) : "无备份目录");
    for (const item of (data.items || []).slice(0, 12)) {
      const li = document.createElement("li");
      const name = document.createElement("span");
      name.textContent = item.name;
      name.title = item.name;
      const meta = document.createElement("em");
      meta.textContent = `${item.kind === "directory" ? "目录" : "文件"} · ${fmtSize(item.size)}`;
      li.append(name, meta);
      list.append(li);
    }
    if (!list.children.length) {
      const li = document.createElement("li");
      li.className = "muted-line";
      li.textContent = "没有备份";
      list.append(li);
    }
  };

  const loadSecurity = async () => {
    if (!csrf) return;
    const data = await getJson("/api/security/pending");
    const banner = $("securityBanner");
    if (!data || !banner) return;
    if (data.available && data.pending) {
      const action = data.action === "delete" ? "删除" : data.action === "overwrite" ? "覆盖" : "发送";
      const target = data.target_name ? `：${data.target_name}` : "";
      const channel = data.channel === "email" ? "邮件审批" : "TOTP";
      $("securityDetail").textContent = `${action}${target} · ${channel} · 剩余 ${data.remaining_seconds}s`;
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
      chatStatus.textContent = "先写一句话再发送。";
      chatStatus.className = "chat-status error";
      return;
    }
    if (!csrf) {
      chatStatus.textContent = "会话未就绪，请刷新页面。";
      chatStatus.className = "chat-status error";
      return;
    }
    chatSend.disabled = true;
    chatStatus.textContent = "发送中…";
    chatStatus.className = "chat-status";
    try {
      const response = await fetch("/api/chat/send", {
        method: "POST",
        credentials: "same-origin",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf },
        body: JSON.stringify({ message: text }),
      });
      const data = await response.json().catch(() => ({}));
      if (!response.ok || !data.ok) {
        chatStatus.textContent = data.message || "发送失败，请稍后再试。";
        chatStatus.className = "chat-status error";
        return;
      }
      appendBubble(text);
      chatText.value = "";
      chatCount.textContent = "0 / 500";
      chatStatus.textContent = "已发送。苏瑾言会在 QQ 回复你。";
      chatStatus.className = "chat-status ok";
    } catch {
      chatStatus.textContent = "网络异常，请稍后再试。";
      chatStatus.className = "chat-status error";
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

  const openFile = async (item) => {
    const modal = $("fileModal");
    const title = $("fileTitle");
    const preview = $("filePreview");
    const meta = $("fileMeta");
    const link = $("fileDownload");
    if (!modal || !title || !preview || !meta || !link) return;
    const url = `/api/files/download?path=${encodeURIComponent(item.path)}`;
    title.textContent = item.name;
    meta.textContent = `${fmtSize(item.size)} · ${new Date(item.mtime * 1000).toLocaleString()}`;
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
        preview.textContent = "文件较大，请直接下载查看。";
        return;
      }
      try {
        const response = await fetch(url, { credentials: "same-origin", cache: "no-store" });
        if (redirectIfUnauthorized(response)) return;
        if (!response.ok) {
          preview.textContent = "预览失败。";
          return;
        }
        const text = await response.text();
        const pre = document.createElement("pre");
        pre.textContent = text;
        preview.append(pre);
      } catch {
        preview.textContent = "预览失败。";
      }
      return;
    }
    preview.textContent = "此类型不支持在线预览，请使用下载按钮。";
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
      li.textContent = "无法读取该目录。";
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
      size.textContent = item.is_dir ? "目录" : fmtSize(item.size);
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
      li.textContent = "这个目录是空的，或文件类型被安全策略隐藏。";
      list.append(li);
    }
  };

  $("logSelect")?.addEventListener("change", loadLogs);
  chatText?.addEventListener("input", () => {
    chatCount.textContent = `${chatText.value.length} / 500`;
  });
  chatSend?.addEventListener("click", () => sendChatMessage(chatText.value));
  document.querySelectorAll("[data-shortcut]").forEach((button) => {
    button.addEventListener("click", () => sendChatMessage(button.dataset.shortcut));
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
      if (data.expires_at) setText("sessionExpiry", new Date(data.expires_at * 1000).toLocaleString());
      loadStatus();
      loadTemps();
      loadUsage();
      loadPlugins();
      loadLogs();
      loadBackups();
      loadSecurity();
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
})();
