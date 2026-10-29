(() => {
  const SUPPORTED = ["zh", "en", "ja", "ko", "es", "fr", "de", "ru"];
  const DEFAULT = "zh";
  const STORAGE_KEY = "cb-lang";
  const LOCALES = {
    zh: "zh-CN", en: "en-US", ja: "ja-JP", ko: "ko-KR",
    es: "es-ES", fr: "fr-FR", de: "de-DE", ru: "ru-RU",
  };
  const NATIVE_NAMES = {
    zh: "中文", en: "English", ja: "日本語", ko: "한국어",
    es: "Español", fr: "Français", de: "Deutsch", ru: "Русский",
  };

  let current = DEFAULT;
  let strings = {};
  let fallback = {};
  let loading = null;

  const normalize = (value) => {
    const code = String(value || "").trim().toLowerCase();
    return SUPPORTED.includes(code) ? code : "";
  };

  const detect = () => {
    try {
      const saved = normalize(localStorage.getItem(STORAGE_KEY));
      if (saved) return saved;
    } catch {
      // localStorage can be unavailable in a private/embedded context.
    }
    const tags = Array.isArray(navigator.languages) && navigator.languages.length
      ? navigator.languages
      : [navigator.language];
    for (const tag of tags) {
      const lower = String(tag || "").toLowerCase();
      if (lower.startsWith("zh")) return "zh";
      for (const code of ["en", "ja", "ko", "es", "fr", "de", "ru"]) {
        if (lower.startsWith(code + "-") || lower === code) return code;
      }
    }
    return DEFAULT;
  };

  const fetchLocale = async (code) => {
    const response = await fetch(`/static/i18n/${code}.json`, {
      credentials: "same-origin",
      cache: "no-store",
    });
    if (!response.ok) throw new Error("locale unavailable");
    const payload = await response.json();
    return payload.strings || {};
  };

  const load = async (code) => {
    const target = normalize(code) || DEFAULT;
    if (!loading || target !== current) {
      loading = (async () => {
        let next;
        try {
          next = await fetchLocale(target);
        } catch {
          next = {};
        }
        if (!Object.keys(next).length && target !== DEFAULT) {
          next = await fetchLocale(DEFAULT);
        }
        if (!Object.keys(fallback).length) {
          try {
            fallback = target === DEFAULT ? next : await fetchLocale(DEFAULT);
          } catch {
            fallback = {};
          }
        }
        strings = next;
        current = target;
      })();
    }
    await loading;
  };

  const interpolate = (value, vars) => {
    if (!vars) return value;
    return String(value).replace(/\{([A-Za-z0-9_]+)\}/g, (match, name) => (
      Object.prototype.hasOwnProperty.call(vars, name) ? String(vars[name]) : match
    ));
  };

  const t = (key, vars) => {
    const value = strings[key] ?? fallback[key] ?? "";
    return interpolate(value, vars);
  };

  const has = (key) => Boolean(strings[key] ?? fallback[key]);

  const number = (value) => {
    const n = Number(value);
    if (!Number.isFinite(n)) return String(value ?? "");
    try {
      return new Intl.NumberFormat(LOCALES[current] || LOCALES[DEFAULT]).format(n);
    } catch {
      return String(n);
    }
  };

  const formatDate = (value, options = {}) => {
    if (value == null) return "";
    const date = value instanceof Date ? value : new Date(value);
    if (Number.isNaN(date.getTime())) return "";
    try {
      return new Intl.DateTimeFormat(LOCALES[current] || LOCALES[DEFAULT], options).format(date);
    } catch {
      return date.toLocaleString();
    }
  };

  const formatSeconds = (value) => t("app.seconds", { seconds: number(value) });

  const formatSize = (bytes) => {
    if (bytes == null) return "—";
    const n = Number(bytes);
    if (!Number.isFinite(n)) return "—";
    if (n < 1024) return `${number(n)} ${t("app.bytes")}`;
    if (n < 1024 * 1024) return `${number((n / 1024).toFixed(1))} ${t("app.kb")}`;
    return `${number((n / 1024 / 1024).toFixed(1))} ${t("app.mb")}`;
  };

  const apply = (root = document) => {
    root.querySelectorAll("[data-i18n]").forEach((node) => {
      const value = t(node.dataset.i18n);
      if (value) node.textContent = value;
    });
    root.querySelectorAll("[data-i18n-placeholder]").forEach((node) => {
      const value = t(node.dataset.i18nPlaceholder);
      if (value) node.setAttribute("placeholder", value);
    });
    root.querySelectorAll("[data-i18n-aria-label]").forEach((node) => {
      const value = t(node.dataset.i18nAriaLabel);
      if (value) node.setAttribute("aria-label", value);
    });
    root.querySelectorAll("[data-i18n-title]").forEach((node) => {
      const value = t(node.dataset.i18nTitle);
      if (value) node.setAttribute("title", value);
    });
  };

  const syncSelectors = () => {
    document.querySelectorAll("[data-language-select]").forEach((select) => {
      if ([...select.options].some((option) => option.value === current)) {
        select.value = current;
      }
    });
  };

  const setLanguage = async (code) => {
    const target = normalize(code);
    if (!target) return false;
    await load(target);
    document.documentElement.lang = current;
    apply(document);
    syncSelectors();
    try {
      localStorage.setItem(STORAGE_KEY, current);
    } catch {
      // Ignore storage failures; the page still uses the in-memory locale.
    }
    window.dispatchEvent(new CustomEvent("cb:languagechange", { detail: { lang: current } }));
    return true;
  };

  const init = async () => {
    await load(detect());
    document.documentElement.lang = current;
    apply(document);
    syncSelectors();
    document.querySelectorAll("[data-language-select]").forEach((select) => {
      select.addEventListener("change", () => setLanguage(select.value));
    });
    return current;
  };

  window.CBI18n = {
    supported: SUPPORTED,
    nativeNames: NATIVE_NAMES,
    locales: LOCALES,
    get current() { return current; },
    t,
    has,
    apply,
    init,
    setLanguage,
    number,
    formatDate,
    formatSeconds,
    formatSize,
    detect,
  };
  window.CBI18nReady = init();
})();
