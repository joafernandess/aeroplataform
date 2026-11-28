/*
 * Loader Control — private admin dashboard.
 * Vanilla JS, no build step. Every piece of data reaches the DOM through
 * textContent (see h()), never innerHTML, so names, notes and loader code
 * cannot inject markup.
 */
"use strict";

const state = { csrf: null, username: null, games: [], timer: null };

// ---------------------------------------------------------------------------
// DOM helpers
// ---------------------------------------------------------------------------
function h(tag, props, ...children) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(props || {})) {
    if (v === null || v === undefined || v === false) continue;
    if (k === "class") el.className = v;
    else if (k === "text") el.textContent = v;
    else if (k.startsWith("on")) el.addEventListener(k.slice(2).toLowerCase(), v);
    else if (k === "value") el.value = v;
    else if (k === "checked") el.checked = Boolean(v);
    else el.setAttribute(k, v === true ? "" : v);
  }
  for (const child of children.flat(Infinity)) {
    if (child === null || child === undefined || child === false) continue;
    el.append(child instanceof Node ? child : document.createTextNode(String(child)));
  }
  return el;
}

const $app = () => document.getElementById("app");

function mount(node) {
  const app = $app();
  app.replaceChildren(node);
}

function toast(message, bad = false) {
  const el = h("div", { class: "toast" + (bad ? " bad" : ""), text: message });
  document.getElementById("toasts").append(el);
  setTimeout(() => {
    el.classList.add("out");
    setTimeout(() => el.remove(), 260);
  }, bad ? 5200 : 3200);
}

async function copy(text, label = "Copied") {
  try {
    await navigator.clipboard.writeText(text);
    toast(label);
  } catch {
    toast("Could not copy — select the text manually.", true);
  }
}

// ---------------------------------------------------------------------------
// Formatting
// ---------------------------------------------------------------------------
function fmtDate(ts) {
  if (!ts) return "—";
  return new Date(ts * 1000).toLocaleString(undefined, {
    year: "numeric", month: "short", day: "2-digit", hour: "2-digit", minute: "2-digit",
  });
}

function ago(ts) {
  if (!ts) return "never";
  const d = Math.floor(Date.now() / 1000) - ts;
  if (d < 0) {
    const f = -d;
    if (f < 3600) return `in ${Math.max(1, Math.round(f / 60))} min`;
    if (f < 86400) return `in ${Math.round(f / 3600)} h`;
    return `in ${Math.round(f / 86400)} d`;
  }
  if (d < 10) return "just now";
  if (d < 60) return `${d}s ago`;
  if (d < 3600) return `${Math.floor(d / 60)} min ago`;
  if (d < 86400) return `${Math.floor(d / 3600)} h ago`;
  return `${Math.floor(d / 86400)} d ago`;
}

function fmtBytes(n) {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / 1024 / 1024).toFixed(2)} MB`;
}

const mask = (key) => (key ? `${key.slice(0, 8)}…` : "—");

const STATUS = {
  ok: ["Active", "ok"],
  inactive: ["Disabled", "warn"],
  revoked: ["Revoked", "bad"],
  banned: ["Banned", "bad"],
  expired: ["Expired", "warn"],
};

function statusPill(status) {
  const [label, cls] = STATUS[status] || [status, ""];
  return h("span", { class: `pill ${cls}`, text: label });
}

function boolPill(on, yes = "Enabled", no = "Disabled") {
  return h("span", { class: `pill ${on ? "ok" : "warn"}`, text: on ? yes : no });
}

function gameName(id) {
  const g = state.games.find((x) => x.id === id);
  return g ? g.name : "—";
}

// ---------------------------------------------------------------------------
// API
// ---------------------------------------------------------------------------
class ApiError extends Error {}

async function api(method, path, body, raw = false) {
  const headers = {};
  let payload;
  if (body !== undefined) {
    if (raw) {
      headers["Content-Type"] = "text/plain; charset=utf-8";
      payload = body;
    } else {
      headers["Content-Type"] = "application/json";
      payload = JSON.stringify(body);
    }
  }
  if (method !== "GET" && state.csrf) headers["X-CSRF-Token"] = state.csrf;
  let res;
  try {
    res = await fetch(`/admin/api/${path}`, {
      method, headers, body: payload, credentials: "same-origin",
    });
  } catch {
    throw new ApiError("Cannot reach the server. Is the bot running?");
  }
  let data = {};
  try { data = await res.json(); } catch { /* empty body */ }
  if (res.status === 401 && path !== "login") {
    const hadSession = Boolean(state.csrf);
    state.csrf = null;
    renderLogin(hadSession ? "Your session ended. Log in again." : "");
    throw new ApiError("Not logged in.");
  }
  if (!res.ok || data.ok === false) {
    const err = new ApiError(data.error || `Error ${res.status}`);
    err.data = data;
    throw err;
  }
  return data;
}

async function loadGames() {
  const data = await api("GET", "games");
  state.games = data.games;
  return data.games;
}

// ---------------------------------------------------------------------------
// Modal
// ---------------------------------------------------------------------------
function modal(title, content, { wide = false } = {}) {
  const close = () => {
    bg.remove();
    document.removeEventListener("keydown", onKey);
  };
  const onKey = (e) => { if (e.key === "Escape") close(); };
  const box = h("div", { class: "modal" + (wide ? " wide" : ""), role: "dialog", "aria-modal": "true" },
    h("h2", { text: title }), content);
  const bg = h("div", { class: "modal-bg", onMousedown: (e) => { if (e.target === bg) close(); } }, box);
  document.body.append(bg);
  document.addEventListener("keydown", onKey);
  const first = box.querySelector("input, select, textarea, button");
  if (first) first.focus();
  return close;
}

function confirmDialog(title, message, actionLabel, danger = true) {
  return new Promise((resolve) => {
    let done = false;
    const finish = (v) => { if (!done) { done = true; close(); resolve(v); } };
    const close = modal(title, h("div", {},
      h("p", { class: "muted", text: message }),
      h("div", { class: "row end" },
        h("button", { class: "btn ghost", text: "Cancel", onClick: () => finish(false) }),
        h("button", { class: "btn " + (danger ? "danger" : "primary"), text: actionLabel, onClick: () => finish(true) }),
      ),
    ));
  });
}

function field(label, input, hint) {
  return h("div", { class: "field" }, h("label", { text: label }), input, hint ? h("div", { class: "hint", text: hint }) : null);
}

function switchInput(checked, onChange) {
  const input = h("input", { type: "checkbox", checked });
  if (onChange) input.addEventListener("change", () => onChange(input.checked, input));
  return { el: h("label", { class: "switch" }, input, h("span")), input };
}

function gameSelect(selected, { allowNone = true, noneLabel = "— Unassigned —" } = {}) {
  const sel = h("select", {},
    allowNone ? h("option", { value: "", text: noneLabel }) : null,
    state.games.map((g) => h("option", { value: String(g.id), text: g.name })));
  sel.value = selected === null || selected === undefined ? "" : String(selected);
  return sel;
}

function gameChecks(selectedIds) {
  const wrap = h("div", { class: "checks" });
  for (const g of state.games) {
    const input = h("input", { type: "checkbox", value: String(g.id), checked: selectedIds.includes(g.id) });
    wrap.append(h("label", { class: "check" }, input, g.name));
  }
  if (!state.games.length) wrap.append(h("span", { class: "muted", text: "No games yet." }));
  return { el: wrap, values: () => [...wrap.querySelectorAll("input:checked")].map((i) => Number(i.value)) };
}

// ---------------------------------------------------------------------------
// Login
// ---------------------------------------------------------------------------
function renderLogin(message) {
  stopTimer();
  const user = h("input", { type: "text", autocomplete: "username", required: true });
  const pass = h("input", { type: "password", autocomplete: "current-password", required: true });
  const code = h("input", { type: "text", inputmode: "numeric", autocomplete: "one-time-code", maxlength: "8", placeholder: "123456" });
  const codeField = field("2FA code", code, "From your authenticator app.");
  codeField.hidden = true;
  const err = h("div", { class: "error", text: message || "" });
  const btn = h("button", { class: "btn primary block", type: "submit", text: "Log in" });
  const form = h("form", {
    onSubmit: async (e) => {
      e.preventDefault();
      btn.disabled = true;
      err.textContent = "";
      try {
        const data = await api("POST", "login", { username: user.value, password: pass.value, code: code.value });
        state.csrf = data.csrf;
        state.username = data.username;
        startShell();
      } catch (ex) {
        err.textContent = ex.message;
        if (ex.data && ex.data.need_code) {
          // Password was right: ask for the second factor and keep the password
          codeField.hidden = false;
          code.value = "";
          code.focus();
        } else {
          pass.value = "";
          code.value = "";
          pass.focus();
        }
      } finally {
        btn.disabled = false;
      }
    },
  }, field("Username", user), field("Password", pass), codeField, btn, err);

  mount(h("div", { class: "login-wrap" },
    h("div", { class: "login-card" },
      h("div", { class: "brand-mark", text: "L" }),
      h("h1", { text: "Loader Control" }),
      h("p", { text: "Private administration. Authorized staff only." }),
      form)));
  user.focus();
}

// ---------------------------------------------------------------------------
// Shell + router
// ---------------------------------------------------------------------------
const ROUTES = [
  ["overview", "Overview"],
  ["games", "Games"],
  ["loaders", "Loaders"],
  ["keys", "Keys"],
  ["shop", "Shop"],
  ["activity", "Activity"],
];

let $main = null;
let $sidebar = null;

function startShell() {
  const links = ROUTES.map(([id, label]) =>
    h("a", { class: "nav-link", href: `#/${id}`, "data-route": id }, h("span", { class: "dot" }), label));
  $sidebar = h("aside", { class: "sidebar" },
    h("div", { class: "brand" },
      h("div", { class: "brand-mark", text: "L" }),
      h("div", {}, h("strong", { text: "Loader Control" }), h("small", { text: "Script loader system" }))),
    h("button", { class: "btn ghost sm nav-toggle", text: "Menu", onClick: () => $sidebar.classList.toggle("open") }),
    h("nav", { class: "nav-links" }, links),
    h("div", { class: "sidebar-foot" },
      h("div", { class: "who", text: `Signed in as ${state.username}` }),
      h("button", {
        class: "btn sm block", text: "Log out",
        onClick: async () => {
          try { await api("POST", "logout", {}); } catch { /* ignore */ }
          state.csrf = null;
          renderLogin("Logged out.");
        },
      })));
  $main = h("main", { class: "main" });
  mount(h("div", { class: "shell" }, $sidebar, $main));
  if (!location.hash) location.hash = "#/overview";
  route();
}

function stopTimer() {
  if (state.timer) clearInterval(state.timer);
  state.timer = null;
}

async function route() {
  if (!$main || !state.csrf) return;
  stopTimer();
  $sidebar.classList.remove("open");
  const parts = location.hash.replace(/^#\/?/, "").split("/");
  const [name, arg] = [parts[0] || "overview", parts[1] ? decodeURIComponent(parts[1]) : null];
  for (const a of $sidebar.querySelectorAll(".nav-link")) {
    a.classList.toggle("active", a.dataset.route === name);
  }
  $main.replaceChildren(h("div", { class: "skeleton" }));
  try {
    await loadGames();
    const view = {
      overview: viewOverview,
      games: viewGames,
      loaders: arg ? () => viewLoader(arg) : viewLoaders,
      keys: arg ? () => viewKey(arg) : viewKeys,
      shop: viewShop,
      activity: viewActivity,
    }[name] || viewOverview;
    await view();
  } catch (ex) {
    if (ex.message !== "Not logged in.") {
      $main.replaceChildren(h("div", { class: "card" }, h("p", { class: "error", text: ex.message })));
    }
  }
}

function page(title, subtitle, actions, ...body) {
  const node = h("div", { class: "page" },
    h("div", { class: "page-head" },
      h("div", {}, h("h1", { text: title }), subtitle ? h("p", { text: subtitle }) : null),
      actions ? h("div", { class: "row" }, actions) : null),
    body);
  $main.replaceChildren(node);
  return node;
}

function table(headers, rows, emptyText = "Nothing here yet.") {
  if (!rows.length) return h("div", { class: "empty", text: emptyText });
  return h("div", { class: "table-wrap" },
    h("table", {},
      h("thead", {}, h("tr", {}, headers.map((t) => h("th", { text: t })))),
      h("tbody", {}, rows)));
}

// ---------------------------------------------------------------------------
// Overview
// ---------------------------------------------------------------------------
function stat(label, value, sub) {
  return h("div", { class: "card stat" },
    h("div", { class: "label", text: label }),
    h("div", { class: "value", text: String(value) }),
    sub ? h("div", { class: "sub", text: sub }) : null);
}

function accessRows(items) {
  return items.map((a) => h("tr", {},
    h("td", { class: "muted", text: ago(a.ts), title: fmtDate(a.ts) }),
    h("td", {}, h("span", { class: `pill ${a.source === "bot" ? "accent" : "info"} plain`, text: a.source === "bot" ? "Bot" : "Execute" })),
    h("td", {}, a.key ? h("a", { class: "mono", href: `#/keys/${encodeURIComponent(a.key)}`, text: mask(a.key) }) : "—"),
    h("td", { text: a.game || "—" }),
    h("td", { class: "mono", text: a.loader_id || "—" }),
    h("td", {}, a.ok ? h("span", { class: "pill ok", text: "OK" }) : h("span", { class: "pill bad", text: "Refused" })),
    h("td", { class: "wrap muted", text: a.reason || "" })));
}

async function viewOverview() {
  const render = async () => {
    const d = await api("GET", "overview");
    const bot = d.bot;
    const info = bot.info || {};
    const node = page("Overview", "Loader system at a glance.", null,
      h("div", { class: "grid stats" },
        stat("Games", d.games.total, `${d.games.enabled} enabled`),
        stat("Loaders", d.loaders.total, `${d.loaders.enabled} enabled · ${d.loaders.unassigned} unassigned`),
        stat("Keys", d.keys.total, `${d.keys.redeemed} redeemed`),
        stat("Active keys", d.keys.active, "usable right now"),
        stat("Inactive keys", d.keys.inactive,
          `${d.keys.by_status.revoked} revoked · ${d.keys.by_status.inactive} disabled · ${d.keys.by_status.banned} banned · ${d.keys.by_status.expired} expired`),
        stat("Requests 24h", d.requests_24h.total, `${d.requests_24h.ok} served`)),
      h("div", { class: "grid two-col" },
        h("div", { class: "card" },
          h("h2", { text: "Bot connection" }),
          h("div", { class: "bot-status" },
            h("span", { class: "pulse" + (bot.online ? " on" : "") }),
            h("div", {},
              h("strong", { text: bot.online ? "Online" : "Offline" }),
              h("div", { class: "muted small", text: bot.last_seen ? `Last heartbeat ${ago(bot.last_seen)}` : "No heartbeat received yet" }))),
          h("dl", { class: "kv" },
            h("dt", { text: "Account" }), h("dd", { text: info.user || "—" }),
            h("dt", { text: "Servers" }), h("dd", { text: info.guilds !== undefined ? String(info.guilds) : "—" }),
            h("dt", { text: "Latency" }), h("dd", { text: info.latency_ms !== undefined ? `${info.latency_ms} ms` : "—" }),
            h("dt", { text: "Up since" }), h("dd", { text: info.started_at ? fmtDate(info.started_at) : "—" }))),
        h("div", { class: "card" },
          h("h2", { text: "Recent activity" }),
          d.recent_activity.length
            ? h("ul", { class: "feed" }, d.recent_activity.map((a) => h("li", {},
              h("span", { class: "when", text: ago(a.ts), title: fmtDate(a.ts) }),
              h("span", { class: "what" }, h("strong", { text: a.actor }), " ", h("span", { class: "muted", text: a.action.replace(/_/g, " ") }), a.detail ? ` — ${a.detail}` : ""))))
            : h("div", { class: "empty", text: "No activity yet." }))),
      d.share_threshold > 0 ? h("div", { class: "card section-gap" },
        h("div", { class: "card-head" },
          h("h2", { text: "Possible key sharing" }),
          h("span", { class: `pill ${d.suspects.length ? "bad" : "ok"}`, text: d.suspects.length ? `${d.suspects.length} key${d.suspects.length > 1 ? "s" : ""}` : "None" })),
        d.suspects.length
          ? table(["Key", "Different IPs (24 h)", "Runs"], d.suspects.map((s) => h("tr", { class: "clickable", onClick: () => { location.hash = `#/keys/${encodeURIComponent(s.key)}`; } },
            h("td", { class: "mono", text: mask(s.key) }),
            h("td", {}, h("span", { class: "pill bad", text: `${s.ips} IPs` })),
            h("td", { text: String(s.runs) }))))
          : h("div", { class: "empty", text: `No key ran from ${d.share_threshold}+ different IPs in the last 24 hours.` })) : null,
      h("div", { class: "card section-gap" },
        h("div", { class: "card-head" }, h("h2", { text: "Latest loader requests" }), h("a", { href: "#/activity", text: "See all" })),
        table(["When", "Source", "Key", "Game", "Loader", "Result", "Reason"], accessRows(d.recent_access), "No requests yet.")));
    return node;
  };
  await render();
  state.timer = setInterval(() => { render().catch(() => {}); }, 30000);
}

// ---------------------------------------------------------------------------
// Games
// ---------------------------------------------------------------------------
function gameForm(game, onSaved) {
  const name = h("input", { type: "text", value: game ? game.name : "", maxlength: "80", required: true });
  const slug = h("input", { type: "text", value: game ? game.slug : "", maxlength: "40", required: true, pattern: "[a-z0-9][a-z0-9-]{1,39}" });
  const places = h("input", { type: "text", value: game ? game.place_ids.join(", ") : "" });
  const enabled = switchInput(game ? game.enabled : true);
  const isDefault = switchInput(game ? game.is_default : false);
  const err = h("div", { class: "error" });
  if (!game) name.addEventListener("input", () => {
    slug.value = name.value.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "")
      .replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 40);
  });
  let close;
  const form = h("form", {
    onSubmit: async (e) => {
      e.preventDefault();
      err.textContent = "";
      const body = {
        name: name.value, slug: slug.value, place_ids: places.value,
        enabled: enabled.input.checked, is_default: isDefault.input.checked,
      };
      try {
        if (game) await api("PATCH", `games/${game.id}`, body);
        else await api("POST", "games", body);
        close();
        toast(game ? "Game saved" : "Game created");
        onSaved();
      } catch (ex) { err.textContent = ex.message; }
    },
  },
  h("div", { class: "form-grid" },
    field("Name", name),
    field("Slug", slug, "Used by the bot and the loader. Lowercase, digits, '-'.")),
  field("Roblox PlaceIds", places, "Optional, comma separated. Lets the universal loader detect this game automatically."),
  h("div", { class: "row" },
    h("label", { class: "check" }, enabled.el, "Enabled"),
    h("label", { class: "check" }, isDefault.el, "Default game (used when no game is detected)")),
  err,
  h("div", { class: "row end section-gap" },
    h("button", { class: "btn ghost", type: "button", text: "Cancel", onClick: () => close() }),
    h("button", { class: "btn primary", type: "submit", text: game ? "Save" : "Create game" })));
  close = modal(game ? `Edit ${game.name}` : "New game", form);
}

async function viewGames() {
  const games = state.games;
  const rows = games.map((g) => {
    const toggle = switchInput(g.enabled, async (on, input) => {
      try {
        await api("PATCH", `games/${g.id}`, { enabled: on });
        toast(`${g.name} ${on ? "enabled" : "disabled"}`);
      } catch (ex) { input.checked = !on; toast(ex.message, true); }
    });
    return h("tr", {},
      h("td", {}, h("strong", { text: g.name }), g.is_default ? h("span", { class: "pill accent plain", text: "Default" }) : null),
      h("td", { class: "mono", text: g.slug }),
      h("td", { class: "mono muted", text: g.place_ids.join(", ") || "—" }),
      h("td", {}, g.loader_count
        ? h("a", { href: "#/loaders", text: `${g.loader_count} loader${g.loader_count > 1 ? "s" : ""}` })
        : h("span", { class: "pill warn", text: "No loader" })),
      h("td", { class: "mono", text: g.active_loader_id ? `${g.active_loader_id.slice(0, 10)}…` : "—", title: g.active_loader_id }),
      h("td", { text: g.restricted_keys ? `${g.restricted_keys} restricted` : "—", class: "muted" }),
      h("td", {}, toggle.el),
      h("td", {}, h("div", { class: "row" },
        h("button", { class: "btn sm", text: "Edit", onClick: () => gameForm(g, route) }),
        h("button", {
          class: "btn sm danger", text: "Delete",
          onClick: async () => {
            const ok = await confirmDialog(`Delete ${g.name}?`,
              "Its loaders become unassigned and keys lose their permission for this game. This cannot be undone.", "Delete game");
            if (!ok) return;
            try { await api("DELETE", `games/${g.id}`); toast("Game deleted"); route(); }
            catch (ex) { toast(ex.message, true); }
          },
        }))));
  });
  page("Games", "Each game has its own loader. Keys can be limited to specific games.",
    h("button", { class: "btn primary", text: "New game", onClick: () => gameForm(null, route) }),
    h("div", { class: "card" },
      table(["Game", "Slug", "PlaceIds", "Loaders", "Serving loader", "Keys", "Enabled", ""], rows,
        "No games yet. Create one to start serving loaders.")));
}

// ---------------------------------------------------------------------------
// Loaders
// ---------------------------------------------------------------------------
function loaderCreateForm() {
  const name = h("input", { type: "text", maxlength: "80", required: true });
  const game = gameSelect(state.games.length ? state.games[0].id : null);
  const enabled = switchInput(true);
  const content = h("textarea", { class: "code", spellcheck: "false", placeholder: "-- Lua code served for this game" });
  const file = h("input", { type: "file", accept: ".lua,.txt,text/plain" });
  file.addEventListener("change", async () => {
    if (!file.files[0]) return;
    const text = await file.files[0].text();
    if (text.length > 1024 * 1024) {
      content.value = "";
      content.placeholder = `${file.files[0].name} (${fmtBytes(file.files[0].size)}) will be uploaded as a file`;
    } else content.value = text;
    if (!name.value) name.value = file.files[0].name.replace(/\.[^.]+$/, "");
  });
  const err = h("div", { class: "error" });
  let close;
  const form = h("form", {
    onSubmit: async (e) => {
      e.preventDefault();
      err.textContent = "";
      try {
        const big = file.files[0] && !content.value;
        const data = await api("POST", "loaders", {
          name: name.value, game_id: game.value || null, enabled: enabled.input.checked,
          content: big ? "" : content.value,
        });
        if (big) await api("PUT", `loaders/${data.loader.id}/content`, await file.files[0].text(), true);
        close();
        toast("Loader created");
        location.hash = `#/loaders/${data.loader.id}`;
      } catch (ex) { err.textContent = ex.message; }
    },
  },
  h("div", { class: "form-grid" }, field("Name", name), field("Game", game)),
  h("label", { class: "check" }, enabled.el, "Enabled"),
  field("Content", content),
  field("…or upload a file", file, "Large scripts (over 1 MB) are uploaded as a file and not shown in the editor."),
  err,
  h("div", { class: "row end" },
    h("button", { class: "btn ghost", type: "button", text: "Cancel", onClick: () => close() }),
    h("button", { class: "btn primary", type: "submit", text: "Create loader" })));
  close = modal("New loader", form, { wide: true });
}

async function viewLoaders() {
  const { loaders } = await api("GET", "loaders");
  const rows = loaders.map((l) => h("tr", { class: "clickable", onClick: () => { location.hash = `#/loaders/${l.id}`; } },
    h("td", {}, h("strong", { text: l.name }), l.serving ? h("span", { class: "pill ok plain", text: "Serving" }) : null),
    h("td", { class: "mono", text: l.id }),
    h("td", {}, l.game_name ? l.game_name : h("span", { class: "pill warn", text: "Unassigned" })),
    h("td", { text: `v${l.version}` }),
    h("td", { class: "muted", text: fmtBytes(l.size) }),
    h("td", { class: "muted", text: ago(l.updated_at), title: fmtDate(l.updated_at) }),
    h("td", {}, boolPill(l.enabled))));
  page("Loaders", "The script each game receives. The newest enabled loader of a game is the one served.",
    h("button", { class: "btn primary", text: "New loader", onClick: loaderCreateForm }),
    h("div", { class: "card" },
      table(["Loader", "ID", "Game", "Version", "Size", "Updated", "Status"], rows, "No loaders yet.")));
}

async function viewLoader(id) {
  const { loader } = await api("GET", `loaders/${encodeURIComponent(id)}`);
  const name = h("input", { type: "text", value: loader.name, maxlength: "80" });
  const game = gameSelect(loader.game_id);
  const enabled = switchInput(loader.enabled);
  const err = h("div", { class: "error" });

  const saveMeta = h("button", {
    class: "btn primary", text: "Save details",
    onClick: async () => {
      err.textContent = "";
      try {
        await api("PATCH", `loaders/${loader.id}`, {
          name: name.value, game_id: game.value || null, enabled: enabled.input.checked,
        });
        toast("Loader saved");
        route();
      } catch (ex) { err.textContent = ex.message; }
    },
  });

  let editor;
  if (loader.too_large || loader.missing) {
    editor = h("div", { class: `notice${loader.missing ? " warn" : ""}`,
      text: loader.missing
        ? "The loader file is missing on disk. Upload the script again."
        : `This loader is ${fmtBytes(loader.size)}, too large to edit here. Download it, edit locally and upload the new version.` });
  } else {
    const code = h("textarea", { class: "code", spellcheck: "false", value: loader.content || "" });
    code.addEventListener("keydown", (e) => {
      if (e.key === "Tab") {
        e.preventDefault();
        const s = code.selectionStart;
        code.setRangeText("    ", s, code.selectionEnd, "end");
      }
    });
    editor = h("div", {},
      code,
      h("div", { class: "row end section-gap" },
        h("button", {
          class: "btn primary", text: "Publish new version",
          onClick: async () => {
            try {
              await api("PATCH", `loaders/${loader.id}`, { content: code.value });
              toast("New version published");
              route();
            } catch (ex) { toast(ex.message, true); }
          },
        })));
  }

  const upload = h("input", { type: "file", accept: ".lua,.txt,text/plain" });
  upload.addEventListener("change", async () => {
    const f = upload.files[0];
    if (!f) return;
    const ok = await confirmDialog("Replace loader content?",
      `Publish ${f.name} (${fmtBytes(f.size)}) as version ${loader.version + 1}? Users get it on their next execution.`,
      "Upload and publish", false);
    if (!ok) { upload.value = ""; return; }
    try {
      await api("PUT", `loaders/${loader.id}/content`, await f.text(), true);
      toast("New version uploaded");
      route();
    } catch (ex) { toast(ex.message, true); }
  });

  page(loader.name, null,
    [
      h("a", { class: "btn", href: `/admin/api/loaders/${loader.id}/download`, text: "Download" }),
      h("button", {
        class: "btn danger", text: "Delete",
        onClick: async () => {
          const ok = await confirmDialog(`Delete ${loader.name}?`,
            "The script file is removed. If this loader is serving a game, that game falls back to its next enabled loader (or none).",
            "Delete loader");
          if (!ok) return;
          try { await api("DELETE", `loaders/${loader.id}`); toast("Loader deleted"); location.hash = "#/loaders"; }
          catch (ex) { toast(ex.message, true); }
        },
      }),
    ],
    h("div", { class: "crumb" }, h("a", { href: "#/loaders", text: "Loaders" }), " / ", h("span", { class: "mono", text: loader.id })),
    h("div", { class: "grid two-col" },
      h("div", { class: "card" },
        h("h2", { text: "Details" }),
        field("Name", name),
        field("Game", game, "A loader serves only the game it is assigned to."),
        h("label", { class: "check" }, enabled.el, "Enabled"),
        err,
        h("div", { class: "row end" }, saveMeta)),
      h("div", { class: "card" },
        h("h2", { text: "Version" }),
        h("dl", { class: "kv" },
          h("dt", { text: "Loader ID" }), h("dd", { class: "mono" }, h("span", { class: "copy", text: loader.id, onClick: () => copy(loader.id) })),
          h("dt", { text: "Version" }), h("dd", { text: `v${loader.version}` }),
          h("dt", { text: "Size" }), h("dd", { text: fmtBytes(loader.size) }),
          h("dt", { text: "SHA-256" }), h("dd", { class: "mono small", text: loader.sha256 || "—" }),
          h("dt", { text: "Last updated" }), h("dd", { text: `${fmtDate(loader.updated_at)} (${ago(loader.updated_at)})` }),
          h("dt", { text: "Created" }), h("dd", { text: fmtDate(loader.created_at) })),
        h("div", { class: "section-gap" }, field("Upload a new version", upload, "Replaces the content without touching the rest of the system.")))),
    h("div", { class: "card section-gap" }, h("h2", { text: "Content" }), editor));
}

// ---------------------------------------------------------------------------
// Keys
// ---------------------------------------------------------------------------
const keyFilters = { q: "", status: "", game: "", page: 1 };

function generateKeysForm() {
  const count = h("input", { type: "number", min: "1", max: "100", value: "1" });
  const days = h("input", { type: "number", min: "0", max: "3650", value: "30" });
  const note = h("input", { type: "text", maxlength: "200", placeholder: "e.g. buyer name" });
  const all = switchInput(true);
  const checks = gameChecks([]);
  checks.el.hidden = true;
  all.input.addEventListener("change", () => { checks.el.hidden = all.input.checked; });
  const err = h("div", { class: "error" });
  let close;
  const form = h("form", {
    onSubmit: async (e) => {
      e.preventDefault();
      err.textContent = "";
      try {
        const data = await api("POST", "keys", {
          count: Number(count.value), days: Number(days.value), note: note.value,
          all_games: all.input.checked, game_ids: checks.values(),
        });
        close();
        showGeneratedKeys(data.keys);
        route();
      } catch (ex) { err.textContent = ex.message; }
    },
  },
  h("div", { class: "form-grid" },
    field("How many", count),
    field("Validity (days)", days, "0 = permanent")),
  field("Note", note),
  h("label", { class: "check" }, all.el, "Access to all games"),
  h("div", { class: "section-gap" }, checks.el),
  err,
  h("div", { class: "row end section-gap" },
    h("button", { class: "btn ghost", type: "button", text: "Cancel", onClick: () => close() }),
    h("button", { class: "btn primary", type: "submit", text: "Generate" })));
  close = modal("Generate keys", form);
}

function showGeneratedKeys(keys) {
  const text = keys.join("\n");
  const close = modal(`${keys.length} key${keys.length > 1 ? "s" : ""} generated`, h("div", {},
    h("p", { class: "muted", text: "Copy them now. They are also listed on the Keys page." }),
    h("div", { class: "keys-out", text }),
    h("div", { class: "row end section-gap" },
      h("button", { class: "btn", text: "Copy all", onClick: () => copy(text, "Keys copied") }),
      h("button", { class: "btn primary", text: "Done", onClick: () => close() }))));
}

async function viewKeys() {
  const params = new URLSearchParams();
  if (keyFilters.q) params.set("q", keyFilters.q);
  if (keyFilters.status) params.set("status", keyFilters.status);
  if (keyFilters.game) params.set("game", keyFilters.game);
  params.set("page", String(keyFilters.page));
  const data = await api("GET", `keys?${params}`);

  const search = h("input", { type: "search", placeholder: "Search key, note or Discord ID…", value: keyFilters.q });
  let debounce;
  search.addEventListener("input", () => {
    clearTimeout(debounce);
    debounce = setTimeout(() => { keyFilters.q = search.value; keyFilters.page = 1; route(); }, 350);
  });
  const status = h("select", {},
    h("option", { value: "", text: "All statuses" }),
    Object.entries(STATUS).map(([v, [label]]) => h("option", { value: v, text: label })));
  status.value = keyFilters.status;
  status.addEventListener("change", () => { keyFilters.status = status.value; keyFilters.page = 1; route(); });
  const game = gameSelect(keyFilters.game, { noneLabel: "All games" });
  game.addEventListener("change", () => { keyFilters.game = game.value; keyFilters.page = 1; route(); });

  const rows = data.items.map((k) => h("tr", { class: "clickable", onClick: () => { location.hash = `#/keys/${encodeURIComponent(k.key)}`; } },
    h("td", { class: "mono", text: mask(k.key) }),
    h("td", {}, statusPill(k.status)),
    h("td", { class: "mono muted", text: k.discord_id || "—" }),
    h("td", { text: k.all_games ? "All games" : (k.game_names.join(", ") || "None") }),
    h("td", { class: "muted", text: k.expires_at ? fmtDate(k.expires_at) : "Never" }),
    h("td", { text: String(k.executions) }),
    h("td", { class: "muted", text: ago(k.last_access || k.last_exec) }),
    h("td", { class: "mono muted", text: k.last_loader_id || "—" }),
    h("td", { class: "wrap muted", text: k.note || "" })));

  const pages = Math.max(1, Math.ceil(data.total / data.per_page));
  const pager = h("div", { class: "pager" },
    h("span", { text: `${data.total} key${data.total === 1 ? "" : "s"}` }),
    h("div", { class: "row" },
      h("button", { class: "btn sm", text: "Previous", disabled: data.page <= 1, onClick: () => { keyFilters.page--; route(); } }),
      h("span", { text: `Page ${data.page} of ${pages}` }),
      h("button", { class: "btn sm", text: "Next", disabled: data.page >= pages, onClick: () => { keyFilters.page++; route(); } })));

  page("Keys", "Generate, restrict, disable and revoke access keys.",
    h("button", { class: "btn primary", text: "Generate keys", onClick: generateKeysForm }),
    h("div", { class: "toolbar" }, search, status, game),
    h("div", { class: "card" },
      table(["Key", "Status", "Discord user", "Games", "Expires", "Runs", "Last access", "Last loader", "Note"], rows, "No keys match."),
      data.items.length ? pager : null));
  if (keyFilters.q) { search.focus(); search.setSelectionRange(search.value.length, search.value.length); }
}

function banDialog(post) {
  const reason = h("input", { type: "text", maxlength: "200", placeholder: "e.g. key sharing" });
  const days = h("input", { type: "number", min: "0", max: "3650", value: "0" });
  let close;
  const form = h("form", {
    onSubmit: (e) => {
      e.preventDefault();
      close();
      post("ban", { reason: reason.value, days: Number(days.value) }, "Key banned");
    },
  },
  field("Reason", reason),
  field("Duration (days)", days, "0 = permanent"),
  h("div", { class: "row end" },
    h("button", { class: "btn ghost", type: "button", text: "Cancel", onClick: () => close() }),
    h("button", { class: "btn danger", type: "submit", text: "Ban key" })));
  close = modal("Ban this key", form);
}

function toDateInput(ts) {
  if (!ts) return "";
  const d = new Date(ts * 1000);
  const pad = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

async function viewKey(key) {
  const { key: k } = await api("GET", `keys/${encodeURIComponent(key)}`);
  const revoked = k.status === "revoked";

  const patch = async (body, message) => {
    try {
      await api("PATCH", `keys/${encodeURIComponent(k.key)}`, body);
      toast(message);
      route();
    } catch (ex) { toast(ex.message, true); }
  };

  // Expiration
  const date = h("input", { type: "date", value: toDateInput(k.expires_at) });
  const expiryCard = h("div", { class: "card" },
    h("h2", { text: "Expiration" }),
    h("p", { class: "muted small", text: k.expires_at ? `Expires ${fmtDate(k.expires_at)} (${ago(k.expires_at)})` : "This key never expires." }),
    field("Expires on", date),
    h("div", { class: "row end" },
      h("button", { class: "btn", text: "Make permanent", disabled: !k.expires_at, onClick: () => patch({ expires_at: null }, "Key is now permanent") }),
      h("button", {
        class: "btn primary", text: "Set date",
        onClick: () => {
          if (!date.value) { toast("Pick a date first.", true); return; }
          const ts = Math.floor(new Date(`${date.value}T23:59:59`).getTime() / 1000);
          patch({ expires_at: ts }, "Expiration updated");
        },
      })));

  // Permissions
  const all = switchInput(k.all_games);
  const checks = gameChecks(k.game_ids);
  checks.el.hidden = k.all_games;
  all.input.addEventListener("change", () => { checks.el.hidden = all.input.checked; });
  const permCard = h("div", { class: "card" },
    h("h2", { text: "Game access" }),
    h("label", { class: "check" }, all.el, "All games"),
    h("div", { class: "section-gap" }, checks.el),
    h("div", { class: "row end section-gap" },
      h("button", {
        class: "btn primary", text: "Save access",
        onClick: () => patch({ all_games: all.input.checked, game_ids: checks.values() }, "Game access saved"),
      })));

  // Note
  const note = h("input", { type: "text", maxlength: "200", value: k.note || "" });
  const noteCard = h("div", { class: "card" },
    h("h2", { text: "Internal note" }),
    field("Note", note),
    h("div", { class: "row end" },
      h("button", { class: "btn primary", text: "Save note", onClick: () => patch({ note: note.value }, "Note saved") })));

  const post = async (path, body, message) => {
    try {
      await api("POST", `keys/${encodeURIComponent(k.key)}/${path}`, body);
      toast(message);
      route();
    } catch (ex) { toast(ex.message, true); }
  };

  const actions = [];
  if (!revoked) {
    actions.push(h("button", {
      class: "btn", text: "Reset HWID", disabled: !k.hwid,
      title: "Lets the buyer register a new PC. Does not use up their resets.",
      onClick: async () => {
        const ok = await confirmDialog("Reset this key's HWID?",
          "The next execution registers a new PC. The buyer's own reset allowance is not used.", "Reset HWID", false);
        if (ok) post("reset-hwid", {}, "HWID reset");
      },
    }));
    actions.push(k.banned
      ? h("button", { class: "btn", text: "Unban", onClick: () => post("unban", {}, "Key unbanned") })
      : h("button", { class: "btn", text: "Ban", onClick: () => banDialog(post) }));
    actions.push(h("button", {
      class: "btn", text: k.active ? "Disable" : "Enable",
      onClick: () => patch({ active: !k.active }, k.active ? "Key disabled" : "Key enabled"),
    }));
    actions.push(h("button", {
      class: "btn danger", text: "Revoke",
      onClick: async () => {
        const ok = await confirmDialog("Revoke this key?",
          "A revoked key stops working everywhere and cannot be enabled again. Use Disable for a temporary block.", "Revoke key");
        if (!ok) return;
        try { await api("POST", `keys/${encodeURIComponent(k.key)}/revoke`, {}); toast("Key revoked"); route(); }
        catch (ex) { toast(ex.message, true); }
      },
    }));
  }

  page("Key details", null, actions,
    h("div", { class: "crumb" }, h("a", { href: "#/keys", text: "Keys" }), " / ", h("span", { class: "mono", text: mask(k.key) })),
    h("div", { class: "grid two-col" },
      h("div", { class: "card" },
        h("div", { class: "card-head" }, h("h2", { text: "Summary" }), statusPill(k.status)),
        h("dl", { class: "kv" },
          h("dt", { text: "Key" }), h("dd", { class: "mono" }, h("span", { class: "copy", text: k.key, title: "Click to copy", onClick: () => copy(k.key, "Key copied") })),
          h("dt", { text: "Discord user" }), h("dd", { class: "mono", text: k.discord_id || "Not redeemed" }),
          h("dt", { text: "Games" }), h("dd", { text: k.all_games ? "All games" : (k.game_names.join(", ") || "None") }),
          h("dt", { text: "Created" }), h("dd", { text: fmtDate(k.created_at) }),
          h("dt", { text: "Redeemed" }), h("dd", { text: fmtDate(k.redeemed_at) }),
          h("dt", { text: "Executions" }), h("dd", { text: String(k.executions) }),
          h("dt", { text: "Last execution" }), h("dd", { text: ago(k.last_exec) }),
          h("dt", { text: "Last access" }), h("dd", { text: ago(k.last_access) }),
          h("dt", { text: "Last loader" }), h("dd", { class: "mono", text: k.last_loader_id || "—" }),
          h("dt", { text: "HWID" }), h("dd", { class: "mono small", text: k.hwid || "Not registered" }),
          h("dt", { text: "HWID resets" }), h("dd", { text: String(k.hwid_resets) }),
          h("dt", { text: "IPs (24 h)" }), h("dd", {},
            k.share_threshold > 0 && k.ips_24h >= k.share_threshold
              ? h("span", { class: "pill bad", text: `${k.ips_24h} different IPs — possible sharing` })
              : String(k.ips_24h)),
          k.banned ? [h("dt", { text: "Ban reason" }), h("dd", { text: k.ban_reason || "—" })] : null,
          k.banned ? [h("dt", { text: "Banned until" }), h("dd", { text: k.ban_until ? fmtDate(k.ban_until) : "Permanent" })] : null,
          k.revoked_at ? [h("dt", { text: "Revoked" }), h("dd", { text: fmtDate(k.revoked_at) })] : null)),
      revoked ? h("div", { class: "card" }, h("h2", { text: "Revoked" }), h("p", { class: "muted", text: "This key was revoked and can no longer be changed." })) : expiryCard),
    revoked ? null : h("div", { class: "grid two-col section-gap" }, permCard, noteCard),
    h("div", { class: "card section-gap" },
      h("h2", { text: "Loader requests with this key" }),
      table(["When", "Source", "Key", "Game", "Loader", "Result", "Reason"], accessRows(k.access), "This key has not requested a loader yet.")));
}

// ---------------------------------------------------------------------------
// Shop settings
// ---------------------------------------------------------------------------
async function viewShop() {
  const { shop, auto_pix: autoPix } = await api("GET", "shop");
  const pay = shop.payments || {};

  const title = h("input", { type: "text", maxlength: "100", value: shop.title || "" });
  const description = h("textarea", { rows: "3", maxlength: "1000", value: shop.description || "" });
  const instructions = h("textarea", { rows: "6", maxlength: "2000", value: shop.instructions || "" });
  const pixType = h("input", { type: "text", maxlength: "60", value: pay.pix_type || "" });
  const pixKey = h("input", { type: "text", maxlength: "200", value: pay.pix_key || "" });
  const paypal = h("input", { type: "text", maxlength: "300", value: pay.paypal_url || "", placeholder: "https://paypal.me/yourname" });
  const err = h("div", { class: "error" });

  const list = h("div");
  const cards = [];
  const addProduct = (p = {}) => {
    const f = {
      id: h("input", { type: "text", maxlength: "40", value: p.id || "" }),
      name: h("input", { type: "text", maxlength: "80", value: p.name || "" }),
      price: h("input", { type: "text", maxlength: "30", value: p.price || "", placeholder: "$9.00" }),
      brl: h("input", { type: "number", min: "0.01", step: "0.01", value: p.price_brl === undefined ? "" : String(p.price_brl), placeholder: "45.00" }),
      days: h("input", { type: "number", min: "0", max: "3650", value: String(p.days === undefined ? 30 : p.days) }),
      description: h("input", { type: "text", maxlength: "200", value: p.description || "" }),
    };
    const card = h("div", { class: "product-card" },
      h("div", { class: "form-grid" },
        field("Name", f.name),
        field("Id", f.id, "Letters, digits, '-' and '_'. Do not change it on a live product."),
        field("Price (shown)", f.price),
        field("Price in BRL", f.brl, autoPix ? "Charged by the automatic Pix." : "Only used when automatic Pix is enabled."),
        field("Validity (days)", f.days, "0 = permanent")),
      field("Description", f.description),
      h("div", { class: "row end" },
        h("button", {
          class: "btn sm danger", type: "button", text: "Remove",
          onClick: () => {
            card.remove();
            cards.splice(cards.indexOf(entry), 1);
          },
        })));
    const entry = { f, card };
    cards.push(entry);
    list.append(card);
  };
  (shop.products || []).forEach(addProduct);

  const save = h("button", {
    class: "btn primary", text: "Save shop",
    onClick: async () => {
      err.textContent = "";
      save.disabled = true;
      try {
        await api("PUT", "shop", {
          title: title.value,
          description: description.value,
          instructions: instructions.value,
          payments: { pix_type: pixType.value, pix_key: pixKey.value, paypal_url: paypal.value },
          products: cards.map(({ f }) => ({
            id: f.id.value, name: f.name.value, price: f.price.value,
            price_brl: f.brl.value, days: f.days.value, description: f.description.value,
          })),
        });
        toast("Shop saved");
      } catch (ex) { err.textContent = ex.message; }
      finally { save.disabled = false; }
    },
  });

  page("Shop", "What buyers see in the shop panel and in their ticket. Saved changes apply right away.", save,
    autoPix ? null : h("div", { class: "notice", text: "Automatic Pix (Mercado Pago) is off. Buyers use the Pix key and you approve payments by hand. Set MERCADOPAGO_ACCESS_TOKEN in the .env to turn it on." }),
    h("div", { class: "grid two-col" },
      h("div", { class: "card" },
        h("h2", { text: "Panel" }),
        field("Title", title),
        field("Description", description, "Markdown works."),
        field("Purchase steps", instructions, "Shown by the How to buy button.")),
      h("div", { class: "card" },
        h("h2", { text: "Payment methods" }),
        field("Pix key type", pixType),
        field("Pix key", pixKey),
        field("PayPal link", paypal, "Leave empty to hide PayPal."))),
    h("div", { class: "card section-gap" },
      h("div", { class: "card-head" },
        h("h2", { text: "Products" }),
        h("button", { class: "btn sm", type: "button", text: "Add product", onClick: () => addProduct({}) })),
      list),
    err);
}

// ---------------------------------------------------------------------------
// Activity
// ---------------------------------------------------------------------------
async function viewActivity() {
  const d = await api("GET", "activity?limit=150");
  page("Activity", "Admin actions and every loader request (bot and executions).", null,
    h("div", { class: "card" },
      h("h2", { text: "Admin & system activity" }),
      table(["When", "Who", "Action", "Detail"], d.activity.map((a) => h("tr", {},
        h("td", { class: "muted", text: fmtDate(a.ts) }),
        h("td", {}, h("strong", { text: a.actor })),
        h("td", {}, h("span", { class: `pill plain ${a.action.includes("fail") || a.action.includes("delete") || a.action.includes("revoke") ? "bad" : "info"}`, text: a.action.replace(/_/g, " ") })),
        h("td", { class: "wrap muted", text: a.detail || "" }))), "No activity yet.")),
    h("div", { class: "card section-gap" },
      h("h2", { text: "Loader requests" }),
      table(["When", "Source", "Key", "Game", "Loader", "Result", "Reason"], accessRows(d.access), "No requests yet.")));
}

// ---------------------------------------------------------------------------
// Boot
// ---------------------------------------------------------------------------
window.addEventListener("hashchange", route);

(async () => {
  try {
    const data = await api("GET", "me");
    state.csrf = data.csrf;
    state.username = data.username;
    startShell();
  } catch (ex) {
    if (ex.message !== "Not logged in.") renderLogin(ex.message);
  }
})();
