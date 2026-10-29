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
  const $ = (id) => document.getElementById(id);
  const account = $("accountEmail");
  const serviceList = $("serviceList");
  const pluginList = $("pluginList");
  const logView = $("logView");
  const chatText = $("chatText");
  const chatCount = $("chatCount");
  const chatStatus = $("chatStatus");
  const chatLog = $("chatLog");
  const chatSend = $("chatSend");

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

  const fmtTime = (epoch) => {
    if (!epoch) return "—";
    return new Date(epoch * 1000).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" });
  };

  const setText = (id, value) => {
    const node = $(id);
    if (node) node.textContent = value;
  };

  const setBar = (id, percent) => {
    const node = $(id);
    if (!node) return;
    const value = Math.max(0, Math.min(100, Number(percent) || 0));
    node.style.width = value + "%";
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

  const loadTemps = async () => {
    if (!csrf) return;
    const data = await getJson("/api/temps");
    if (!data) return;
    if (!data.ok) {
      setText("tempSource", data.error ? "监控暂不可用：" + data.error : "监控暂不可用");
      return;
    }
    const cpu = data.cpu;
    const gpu = data.gpu;
    setText("cpuValue", cpu == null ? "—" : cpu.toFixed(1) + " °C");
    setText("gpuValue", gpu == null ? "—" : gpu.toFixed(1) + " °C");
    setBar("cpuBar", cpu == null ? 0 : cpu);
    setBar("gpuBar", gpu == null ? 0 : gpu);
    const used = data.vram_used;
    const total = data.vram_total;
    const vramPct = used != null && total ? (used / total) * 100 : 0;
    setText("vramValue", used != null && total ? `${Math.round(used)} / ${Math.round(total)} MB` : "—");
    setBar("vramBar", vramPct);
    setText("tempSource", (data.source || "传感器") + (data.gpu_load != null ? ` · GPU 占用 ${Math.round(data.gpu_load)}%` : ""));
    setText("tempsUpdated", new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }));
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

  const sendChat = async () => {
    const message = chatText.value.trim();
    if (!message) {
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
        body: JSON.stringify({ message }),
      });
      const data = await response.json().catch(() => ({}));
      if (!response.ok || !data.ok) {
        chatStatus.textContent = data.message || "发送失败，请稍后再试。";
        chatStatus.className = "chat-status error";
        return;
      }
      const empty = chatLog?.querySelector(".chat-empty");
      if (empty) empty.remove();
      const bubble = document.createElement("div");
      bubble.className = "chat-bubble user";
      bubble.textContent = message;
      chatLog?.append(bubble);
      if (chatLog) chatLog.scrollTop = chatLog.scrollHeight;
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

  $("logSelect")?.addEventListener("change", loadLogs);
  chatText?.addEventListener("input", () => {
    chatCount.textContent = `${chatText.value.length} / 500`;
  });
  chatSend?.addEventListener("click", sendChat);

  fetch("/api/auth/me", { credentials: "same-origin", cache: "no-store" })
    .then((response) => {
      if (redirectIfUnauthorized(response)) return null;
      return response.json();
    })
    .then((data) => {
      if (!data || !data.ok) return;
      csrf = data.csrf;
      account.textContent = data.email;
      if (data.expires_at) {
        setText("sessionExpiry", new Date(data.expires_at * 1000).toLocaleString());
      }
      loadStatus();
      loadTemps();
      loadPlugins();
      loadLogs();
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
  setInterval(loadPlugins, 30000);
})();
