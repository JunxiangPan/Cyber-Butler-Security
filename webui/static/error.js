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
  const status = String(document.body.dataset.errorStatus || "500");
  const known = ["403", "404", "500"].includes(status) ? status : "500";
  const render = () => {
    document.getElementById("errorTitle").textContent = i18n.t(`error.${known}.title`);
    document.getElementById("errorMessage").textContent = i18n.t(`error.${known}.message`);
  };
  (async () => {
    await (window.CBI18nReady || i18n.init());
    render();
    window.addEventListener("cb:languagechange", render);
  })();
})();
