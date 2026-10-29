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
  const account = document.getElementById("accountEmail");
  const expiry = document.getElementById("sessionExpiry");

  const formatExpiry = (epoch) => {
    if (!epoch) return "—";
    return new Date(epoch * 1000).toLocaleString();
  };

  fetch("/api/auth/me", { credentials: "same-origin", cache: "no-store" })
    .then((response) => {
      if (response.status === 401) {
        window.location.replace("/");
        return null;
      }
      return response.json();
    })
    .then((data) => {
      if (!data || !data.ok) return;
      csrf = data.csrf;
      account.textContent = data.email;
      expiry.textContent = formatExpiry(data.expires_at);
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
})();
