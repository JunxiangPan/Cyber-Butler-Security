(() => {
  const root = document.documentElement;
  const stored = localStorage.getItem("cb-theme");
  const preferred = window.matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark";
  root.dataset.theme = stored || preferred;

  const toggle = document.getElementById("themeToggle");
  toggle?.addEventListener("click", () => {
    root.dataset.theme = root.dataset.theme === "dark" ? "light" : "dark";
    localStorage.setItem("cb-theme", root.dataset.theme);
  });

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

  const setStatus = (message, kind = "") => {
    status.textContent = message;
    status.className = "auth-status" + (kind ? " " + kind : "");
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

  const startCountdown = () => {
    remaining = 60;
    resendButton.disabled = true;
    clearInterval(countdownTimer);
    const tick = () => {
      resendButton.textContent = remaining > 0 ? `重新发送（${remaining}s）` : "重新发送";
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
      setStatus("请输入管理员邮箱。", "error");
      return;
    }
    setStatus("正在发送验证码…");
    sendButton.disabled = true;
    resendButton.disabled = true;
    try {
      const { response, data } = await postJson("/api/auth/request-otp", { email });
      if (!response.ok) {
        setStatus(data.message || "发送失败，请稍后重试。", "error");
        return;
      }
      currentEmail = email;
      sentEmail.textContent = email;
      emailStep.hidden = true;
      codeStep.hidden = false;
      codeInput.value = "";
      codeInput.focus();
      setStatus(data.message || "验证码已发送。", "ok");
      startCountdown();
    } catch {
      setStatus("网络异常，请稍后重试。", "error");
    } finally {
      sendButton.disabled = false;
    }
  };

  const verifyCode = async () => {
    const code = codeInput.value.trim();
    if (!/^\d{6}$/.test(code)) {
      setStatus("请输入 6 位数字验证码。", "error");
      return;
    }
    setStatus("正在验证…");
    verifyButton.disabled = true;
    try {
      const { response, data } = await postJson("/api/auth/verify", { email: currentEmail, code });
      if (!response.ok) {
        setStatus(data.message || "验证码不正确。", "error");
        return;
      }
      setStatus("登录成功，正在进入控制台…", "ok");
      window.location.replace("/");
    } catch {
      setStatus("网络异常，请稍后重试。", "error");
    } finally {
      verifyButton.disabled = false;
    }
  };

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
})();
