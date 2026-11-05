(() => {
  const $ = (id) => document.getElementById(id);
  let csrf = "";

  const setText = (id, value) => {
    const node = $(id);
    if (node) node.textContent = value;
  };

  const api = async (url, options = {}) => {
    const init = { credentials: "same-origin", cache: "no-store", ...options };
    init.headers = { ...(options.headers || {}) };
    if (csrf && (init.method || "GET").toUpperCase() !== "GET") {
      init.headers["X-CSRF-Token"] = csrf;
    }
    const response = await fetch(url, init);
    if (response.status === 401) {
      window.location.replace("/");
      return null;
    }
    return response.json().catch(() => ({}));
  };

  const loadPending = async () => {
    const data = await api("/api/security/pending");
    if (!data) return;
    const card = $("pendingCard");
    const empty = $("pendingEmpty");
    if (!data.pending) {
      if (card) card.hidden = true;
      if (empty) empty.hidden = false;
      setText("pendingStatus", data.available ? "" : "Broker 暂不可用 / Broker unavailable");
      return;
    }
    if (empty) empty.hidden = true;
    if (card) card.hidden = false;
    setText("pendingAction", data.action || "request");
    setText("pendingTarget", data.target_name || "");
    setText("pendingScope", data.scope_root || "");
    $("pendingCard").dataset.id = data.id || "";
    setText("pendingStatus", "");
  };

  const verifyPending = async () => {
    const card = $("pendingCard");
    const id = card.dataset.id || "";
    const code = $("pendingCode").value.trim();
    if (!id || !code) {
      setText("pendingStatus", "请输入验证码 / Enter a code");
      return;
    }
    const data = await api("/api/security/pending/verify", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id, code }),
    });
    if (!data) return;
    setText("pendingStatus", data.ok ? "已批准 / Approved" : (data.error || "验证失败 / Verification failed"));
    $("pendingCode").value = "";
    await loadPending();
  };

  const loadNetwork = async () => {
    const data = await api("/api/security/network-policy");
    if (!data || !data.ok) return;
    const domains = (data.policy?.allow || [])
      .filter((item) => item.kind === "domain")
      .map((item) => item.name);
    $("networkDomains").value = domains.join("\n");
    const guard = data.guard?.healthy ? "运行中 / running" : "未运行 / unavailable";
    setText("networkStatus", "仅 Audit · 门卫 " + guard);
  };

  const saveNetwork = async () => {
    const data = await api("/api/security/network-policy", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        mode: "audit",
        domains: $("networkDomains").value,
        block_unknown: true,
      }),
    });
    if (!data) return;
    setText("networkStatus", data.ok ? "已保存（仅审计）/ Saved (audit only)" : (data.message || "保存失败 / Save failed"));
  };

  const loadTotpBinding = async () => {
    const data = await api("/api/security/totp-bind");
    if (!data) return;
    if (!data.ok) {
      setText("totpInfo", data.message || "无法读取绑定信息 / Binding unavailable");
      return;
    }
    const lines = [];
    if (data.issuer) lines.push("Issuer: " + data.issuer);
    if (data.account) lines.push("Account: " + data.account);
    if (data.secret) lines.push("Secret: " + data.secret);
    if (data.uri) lines.push("URI: " + data.uri);
    setText("totpInfo", lines.join("\n") || "没有可显示的绑定信息 / No binding data");
  };

  const logout = async () => {
    await api("/api/auth/logout", { method: "POST" });
    window.location.replace("/");
  };

  const init = async () => {
    const me = await api("/api/auth/me");
    if (!me || !me.ok) return;
    csrf = me.csrf || "";
    setText("accountEmail", me.email || "");
    $("pendingRefresh")?.addEventListener("click", loadPending);
    $("pendingVerify")?.addEventListener("click", verifyPending);
    $("networkRefresh")?.addEventListener("click", loadNetwork);
    $("networkSave")?.addEventListener("click", saveNetwork);
    $("totpBind")?.addEventListener("click", loadTotpBinding);
    $("logoutButton")?.addEventListener("click", logout);
    await loadPending();
    await loadNetwork();
    setInterval(loadPending, 5000);
  };

  init().catch(() => {});
})();
