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

  const emailStep = document.getElementById("emailStep");
  const codeStep = document.getElementById("codeStep");
  const emailInput = document.getElementById("email");
  const codeInput = document.getElementById("code");
  const sentEmail = document.getElementById("sentEmail");
  const status = document.getElementById("authStatus");
  const sendButton = document.getElementById("sendCode");
  const verifyButton = document.getElementById("verifyCode");
  const resendButton = document.getElementById("resendCode");
  const changeButton = document.getElementById("changeEmail");

  let currentEmail = "";
  let countdownTimer = null;
  let remaining = 0;
  let statusState = { key: "", text: "", vars: null, kind: "" };

  const CODE_KEYS = {
    "auth.rate_limited": "auth.error.rate",
    "auth.mailer_failed": "auth.error.mailer",
    "auth.invalid_code": "auth.error.codeInvalid",
    "auth.otp_sent": "auth.status.sent",
    "auth.ok": "auth.status.success",
  };

  const codeKey = (data) => (data && data.code ? CODE_KEYS[data.code] || "" : "");

  const renderStatus = () => {
    if (statusState.key) {
      status.textContent = i18n.t(statusState.key, statusState.vars);
    } else {
      status.textContent = statusState.text || "";
    }
    status.className = "auth-status" + (statusState.kind ? " " + statusState.kind : "");
  };

  const setStatus = (key, vars = null, kind = "") => {
    statusState = { key, text: "", vars, kind };
    renderStatus();
  };

  const setStatusFromResponse = (data, fallbackKey, kind) => {
    if (data && data.code && i18n.has(data.code)) {
      setStatus(data.code, null, kind);
      return;
    }
    if (data && data.message) {
      statusState = { key: "", text: data.message, vars: null, kind };
      status.className = "auth-status" + (kind ? " " + kind : "");
      return;
    }
    setStatus(fallbackKey, null, kind);
  };

  const postJson = async (url, body) => {
    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      credentials: "same-origin",
      body: JSON.stringify(body),
    });
    const data = await response.json().catch(() => ({}));
    return { response, data };
  };

  const renderCountdown = () => {
    resendButton.textContent = remaining > 0
      ? i18n.t("auth.resendCountdown", { seconds: i18n.number(remaining) })
      : i18n.t("auth.resend");
  };

  const startCountdown = () => {
    remaining = 60;
    resendButton.disabled = true;
    clearInterval(countdownTimer);
    const tick = () => {
      renderCountdown();
      if (remaining <= 0) {
        resendButton.disabled = false;
        clearInterval(countdownTimer);
        return;
      }
      remaining -= 1;
    };
    tick();
    countdownTimer = setInterval(tick, 1000);
  };

  const requestCode = async () => {
    const email = emailInput.value.trim().toLowerCase();
    if (!email) {
      setStatus("auth.error.emailRequired", null, "error");
      return;
    }
    setStatus("auth.status.sending");
    sendButton.disabled = true;
    resendButton.disabled = true;
    try {
      const { response, data } = await postJson("/api/auth/request-otp", {
        email,
        lang: i18n.current,
      });
      if (!response.ok) {
        const mapped = codeKey(data);
        if (mapped) setStatus(mapped, null, "error");
        else if (data && data.message) setStatusFromResponse(data, "auth.error.sendFailed", "error");
        else if (response.status === 429) setStatus("auth.error.rate", null, "error");
        else setStatus("auth.error.sendFailed", null, "error");
        return;
      }
      currentEmail = email;
      sentEmail.textContent = email;
      emailStep.hidden = true;
      codeStep.hidden = false;
      codeInput.value = "";
      codeInput.focus();
      setStatus("auth.status.sent", null, "ok");
      startCountdown();
    } catch {
      setStatus("auth.error.network", null, "error");
    } finally {
      sendButton.disabled = false;
    }
  };

  const verifyCode = async () => {
    const code = codeInput.value.trim();
    if (!/^\d{6}$/.test(code)) {
      setStatus("auth.error.codeFormat", null, "error");
      return;
    }
    setStatus("auth.status.verifying");
    verifyButton.disabled = true;
    try {
      const { response, data } = await postJson("/api/auth/verify", {
        email: currentEmail,
        code,
        lang: i18n.current,
      });
      if (!response.ok) {
        const mapped = codeKey(data);
        if (mapped) setStatus(mapped, null, "error");
        else if (data && data.message) setStatusFromResponse(data, "auth.error.codeInvalid", "error");
        else if (response.status === 429) setStatus("auth.error.rate", null, "error");
        else setStatus("auth.error.codeInvalid", null, "error");
        return;
      }
      setStatus("auth.status.success", null, "ok");
      window.location.replace("/");
    } catch {
      setStatus("auth.error.network", null, "error");
    } finally {
      verifyButton.disabled = false;
    }
  };

  const initialize = async () => {
    await (window.CBI18nReady || i18n.init());
    renderStatus();
    renderCountdown();
    window.addEventListener("cb:languagechange", () => {
      renderStatus();
      renderCountdown();
    });
    emailStep?.addEventListener("submit", (event) => {
      event.preventDefault();
      requestCode();
    });
    codeStep?.addEventListener("submit", (event) => {
      event.preventDefault();
      verifyCode();
    });
    resendButton?.addEventListener("click", requestCode);
    changeButton?.addEventListener("click", () => {
      clearInterval(countdownTimer);
      codeStep.hidden = true;
      emailStep.hidden = false;
      setStatus("");
      emailInput.focus();
    });
    codeInput?.addEventListener("input", () => {
      codeInput.value = codeInput.value.replace(/\D/g, "").slice(0, 6);
    });
  };

  initialize();
})();
