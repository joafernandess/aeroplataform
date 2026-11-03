/* ==========================================================================
   AERO Admin Dashboard — app.js
   Vanilla JS SPA. Talks to /api/v1 (session cookie). No fake data: every
   value comes from the backend or is explicitly marked as unavailable.
   ========================================================================== */
"use strict";

const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

const state = {
  me: null,           // {id, email, role, must_change}
  keysPage: 0,
  keysSearch: "",
  keysStatus: "",
  usersPage: 0,
  usersSearch: "",
  evKind: "",
};

/* --------------------------------------------------------------------------
 * API helper
 * ------------------------------------------------------------------------ */
async function api(method, path, body = undefined) {
  const opts = { method, headers: {} };
  if (body !== undefined) {
    opts.headers["Content-Type"] = "application/json";
    opts.body = JSON.stringify(body);
  }
  let resp, data;
  try {
    resp = await fetch("/api/v1" + path, opts);
    data = await resp.json();
  } catch (err) {
    return { ok: false, status: 0, error: "Network error — backend down?" };
  }
  if (!data || data.ok === undefined) {
    return { ok: false, status: resp.status, error: "Malformed API response" };
  }
  if (data.ok) {
    return { ok: true, status: resp.status, data: data.data };
  }
  return { ok: false, status: resp.status, error: data.error || "API error" };
}

/* --------------------------------------------------------------------------
 * Formatting
 * ------------------------------------------------------------------------ */
function fmtDate(ts) {
  if (!ts) return "—";
  const d = new Date(ts * 1000);
  const p = (n) => String(n).padStart(2, "0");
  return `${p(d.getDate())}/${p(d.getMonth() + 1)}/${d.getFullYear()} ${p(d.getHours())}:${p(d.getMinutes())}`;
}
function fmtTime(ts) {
  if (!ts) return "—";
  const d = new Date(ts * 1000);
  const p = (n) => String(n).padStart(2, "0");
  return `${p(d.getDate())}/${p(d.getMonth() + 1)} ${p(d.getHours())}:${p(d.getMinutes())}`;
}
function fmtMoney(cents) {
  if (cents === null || cents === undefined) return "—";
  return "$" + (cents / 100).toFixed(2);
}
function esc(str) {
  return String(str ?? "")
    .replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;").replaceAll("'", "&#39;");
}
function badge(kind, label) {
  return `<span class="badge ${esc(kind)}">${esc(label)}</span>`;
}
async function copyText(text) {
  try {
    await navigator.clipboard.writeText(text);
    toast("Copied to clipboard", "ok");
  } catch {
    prompt("Copy manually:", text);
  }
}

/* --------------------------------------------------------------------------
 * Toast + modal
 * ------------------------------------------------------------------------ */
function toast(msg, kind = "") {
  const el = document.createElement("div");
  el.className = `toast ${kind}`;
  el.textContent = msg;
  $("#toast-wrap").append(el);
  setTimeout(() => el.remove(), 3600);
}

function openModal(html, wide = false) {
  const modal = $("#modal");
  modal.className = wide ? "modal wide" : "modal";
  modal.innerHTML = html;
  $("#modal-backdrop").hidden = false;
  return modal;
}
function closeModal() {
  $("#modal-backdrop").hidden = true;
  $("#modal").innerHTML = "";
}
$("#modal-backdrop").addEventListener("mousedown", (e) => {
  if (e.target === e.currentTarget) closeModal();
});
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape" && !$("#modal-backdrop").hidden) closeModal();
});

function confirmModal(title, message, danger = true) {
  return new Promise((resolve) => {
    const m = openModal(`
      <h2>${esc(title)}</h2>
      <p class="hint">${esc(message)}</p>
      <div class="modal-actions">
        <button class="btn btn-ghost" data-x="no">Cancel</button>
        <button class="btn ${danger ? "btn-danger" : ""}" data-x="yes">Confirm</button>
      </div>`);
    m.querySelector('[data-x="no"]').onclick = () => { closeModal(); resolve(false); };
    m.querySelector('[data-x="yes"]').onclick = () => { closeModal(); resolve(true); };
  });
}

/* --------------------------------------------------------------------------
 * Session
 * ------------------------------------------------------------------------ */
async function loadMe() {
  const r = await api("GET", "/me");
  if (!r.ok) return null;
  state.me = r.data;
  return state.me;
}

function applyWhoami() {
  $("#whoami").textContent = state.me?.email || "";
  $("#must-change-note").hidden = !state.me?.must_change;
  const role = state.me?.role;
  $("#whoami").title = role === "owner" ? "Full access (owner)"
    : role === "service" ? "API service token"
    : "Limited access (staff)";
}

function showLogin() {
  $("#app-view").hidden = true;
  $("#login-view").hidden = false;
  $("#login-email").focus();
}
function showApp() {
  $("#login-view").hidden = true;
  $("#app-view").hidden = false;
  applyWhoami();
  switchView(currentView);
}

$("#login-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const errBox = $("#login-error");
  errBox.hidden = true;
  const email = $("#login-email").value.trim();
  const password = $("#login-password").value;
  $("#login-submit").disabled = true;
  const r = await api("POST", "/login", { email, password });
  $("#login-submit").disabled = false;
  if (!r.ok) {
    errBox.textContent = r.error;
    errBox.hidden = false;
    return;
  }
  state.me = r.data;
  $("#login-password").value = "";
  showApp();
});
$("#logout-btn").addEventListener("click", async () => {
  await api("POST", "/logout");
  showLogin();
});

/* --------------------------------------------------------------------------
 * View switching
 * ------------------------------------------------------------------------ */
let currentView = "overview";
const VIEW_TITLES = {
  overview: "Overview", keys: "Key Management", scripts: "Script Management",
  catalog: "Catalog — Games · Licenses · Products", users: "Users",
  sales: "Sales", activity: "Activity & Audit", settings: "Settings & API",
};

$$(".nav-btn").forEach((btn) => {
  btn.addEventListener("click", () => switchView(btn.dataset.view));
});
function switchView(view) {
  currentView = view;
  $$(".nav-btn").forEach((b) => b.classList.toggle("active", b.dataset.view === view));
  $$(".view").forEach((v) => { v.hidden = v.id !== `view-${view}`; });
  $("#view-title").textContent = VIEW_TITLES[view] || view;
  renderView(view);
}

async function renderView(view) {
  const loaders = {
    overview: renderOverview,
    keys: renderKeys,
    scripts: renderScripts,
    catalog: renderCatalog,
    users: renderUsers,
    sales: renderSales,
    activity: renderActivity,
    settings: renderSettings,
  };
  try {
    await (loaders[view] || (() => {}))();
  } catch (err) {
    toast(`Failed to load ${view}: ${err.message}`, "err");
  }
}
function reloadCurrent() {
  renderView(currentView);
}

/* --------------------------------------------------------------------------
 * OVERVIEW
 * ------------------------------------------------------------------------ */
async function renderOverview() {
  const r = await api("GET", "/overview");
  if (!r.ok) return toast(r.error, "err");
  const o = r.data;
  const k = o.keys || {};
  const cards = [
    ["Users", o.users, "total registered"],
    ["Active keys", k.active, "not revoked/banned, not expired"],
    ["Redeemed keys", k.redeemed, "bound to a user"],
    ["Expired keys", k.expired, "past expiration"],
    ["Revoked keys", k.revoked, "staff revoked"],
    ["Banned keys", k.banned, "currently banned"],
    ["Scripts", o.scripts && `${o.scripts.enabled}/${o.scripts.total}`,
      `${o.scripts?.versions ?? 0} published versions`],
    ["Games", o.games && `${o.games.active}/${o.games.total}`, "active/total"],
    ["Revenue (30d)", fmtMoney(o.sales?.revenue_30d_cents ?? null),
      `total all-time: ${fmtMoney(o.sales?.revenue_total_cents ?? null)}`],
    ["API events (7d)", o.api?.events_7d?.ok_total ?? 0,
      `${o.api?.events_7d?.denied_total ?? 0} denied · ${o.api?.events_7d?.rate_limited_total ?? 0} rate-limited`],
    ["Uptime", humanUptime(o.api?.uptime_seconds ?? 0), "since backend start"],
  ];
  $("#stat-grid").innerHTML = cards.map(([label, value, sub]) => `
    <div class="stat">
      <div class="v">${esc(value ?? "—")}</div>
      <div class="k">${esc(label)}</div>
      <div class="s">${esc(sub)}</div>
    </div>`).join("");

  $("#ov-events tbody").innerHTML = (o.recent || []).slice(0, 12).map((e) => `
    <tr>
      <td>${fmtTime(e.ts)}</td>
      <td>${esc(e.kind)}</td>
      <td>${e.result ? badge(e.result === "ok" ? "ok" : "denied", e.result) : badge("neutral", "—")}</td>
      <td class="mono">${esc(e.key ? e.key.slice(0, 12) + "…" : "")}</td>
      <td title="${esc(e.reason || e.detail || "")}">${esc(e.reason || e.detail || "—")}</td>
    </tr>`).join("") || `<tr><td colspan="5" class="muted">No events yet</td></tr>`;

  $("#ov-audit tbody").innerHTML = (o.audit || []).slice(0, 12).map((a) => `
    <tr>
      <td>${fmtTime(a.ts)}</td>
      <td>${esc(a.actor || "—")}</td>
      <td>${esc(a.action)}</td>
      <td>${esc(a.target || "—")}</td>
    </tr>`).join("") || `<tr><td colspan="4" class="muted">No actions yet</td></tr>`;
}

function humanUptime(sec) {
  const d = Math.floor(sec / 86400), h = Math.floor(sec % 86400 / 3600), m = Math.floor(sec % 3600 / 60);
  if (d) return `${d}d ${h}h`;
  if (h) return `${h}h ${m}m`;
  return `${m}m`;
}

/* --------------------------------------------------------------------------
 * KEYS
 * ------------------------------------------------------------------------ */
const KEYS_PER_PAGE = 25;
const STATUS_LABEL = { active: "Active", expired: "Expired", banned: "Banned", revoked: "Revoked" };

function keyRowCountdown(row) {
  if (row.status === "active" && row.expires_at) {
    const left = row.expires_at - Date.now() / 1000;
    if (left > 0) {
      const d = Math.floor(left / 86400), h = Math.floor(left % 86400 / 3600);
      return d ? ` (${d}d ${h}h left)` : ` (${h}h left)`;
    }
  }
  return "";
}

async function renderKeys() {
  const q = new URLSearchParams({
    limit: KEYS_PER_PAGE, offset: state.keysPage * KEYS_PER_PAGE,
  });
  if (state.keysSearch) q.set("search", state.keysSearch);
  if (state.keysStatus) q.set("status", state.keysStatus);
  const r = await api("GET", `/keys?${q}`);
  if (!r.ok) return toast(r.error, "err");
  const { rows, total } = r.data;
  $("#keys-total").textContent = `${total} key${total === 1 ? "" : "s"}`;
  $("#keys-table tbody").innerHTML = rows.map((k) => `
    <tr data-key="${esc(k.key)}">
      <td class="mono" title="click to copy">${esc(k.key)}</td>
      <td>${badge(k.status, STATUS_LABEL[k.status] || k.status)}</td>
      <td>${k.discord_id ? `${esc(k.display_name || "user")} <span class="muted mono">${esc(String(k.discord_id))}</span>` : "—"}</td>
      <td>${esc(k.product_name || "—")}</td>
      <td>${k.expires_at === null ? badge("active", "Permanent") : esc(fmtDate(k.expires_at) + keyRowCountdown(k))}</td>
      <td>${k.executions}</td>
      <td class="mono">${k.hwid ? esc(k.hwid.slice(0, 10) + "…") : "—"}</td>
      <td>${fmtDate(k.created_at)}</td>
      <td>
        <div style="display:flex;gap:5px">
          <button class="btn btn-ghost btn-sm" data-act="reset-hwid" title="Reset HWID">HWID</button>
          <button class="btn btn-ghost btn-sm" data-act="revoke">Revoke</button>
          <button class="btn btn-ghost btn-sm" data-act="ban" title="Ban with reason/days">Ban</button>
          <button class="btn btn-ghost btn-sm" data-act="extend" title="Extend days (checkbox = permanent)">Extend</button>
          <button class="btn btn-ghost btn-sm" data-act="unbind" title="Unbind from user">Unbind</button>
          <button class="btn btn-ghost btn-sm" data-act="note" title="Set internal note">Note</button>
        </div>
      </td>
    </tr>`).join("") || `<tr><td colspan="9" class="muted">No keys found${state.keysSearch ? " for this search" : ""}</td></tr>`;

  $("#keys-total").dataset.total = String(total);
}

$("#keys-table").addEventListener("click", (e) => {
  const btn = e.target.closest("[data-act]");
  if (btn) {
    const row = btn.closest("tr[data-key]");
    return openKeyActionModal(btn.dataset.act, row.dataset.key);
  }
  const row = e.target.closest("tr[data-key]");
  if (row && e.target.closest("td.mono")) copyText(row.dataset.key);
});

$("#keys-search").addEventListener("input", debounce(() => {
  state.keysSearch = $("#keys-search").value.trim();
  state.keysPage = 0;
  renderKeys();
}, 300));
$("#keys-status").addEventListener("change", (e) => {
  state.keysStatus = e.target.value;
  state.keysPage = 0;
  renderKeys();
});
$("#keys-prev").onclick = () => { if (state.keysPage > 0) { state.keysPage--; renderKeys(); } };
$("#keys-next").onclick = () => { state.keysPage++; renderKeys(); };
$("#keys-gen-btn").onclick = keysGenerateModal;

function debounce(fn, ms) {
  let t;
  return (...args) => { clearTimeout(t); t = setTimeout(() => fn(...args), ms); };
}

async function openKeyActionModal(action, key) {
  switch (action) {
    case "revoke": {
      if (!await confirmModal("Revoke key", `${key}\n\nAll executions will be denied (AutoKick denies heartbeats instantly).`)) return;
      const r = await api("POST", "/keys/revoke", { key });
      r.ok ? toast("Key revoked", "ok") : toast(r.error, "err");
      reloadCurrent(); break;
    }
    case "restore": {
      const r = await api("POST", "/keys/restore", { key });
      r.ok ? toast("Key restored", "ok") : toast(r.error, "err");
      reloadCurrent(); break;
    }
    case "reset-hwid": {
      const r = await api("POST", "/keys/reset-hwid", { key });
      r.ok ? toast("HWID reset — next execution binds a new HWID", "ok")
           : toast(r.error, "err");
      reloadCurrent(); break;
    }
    case "unbind": {
      if (!await confirmModal("Unbind key", "Remove the bound user, HWID and reset counter (e.g. refund/transfer)?")) return;
      const r = await api("POST", "/keys/unbind", { key });
      r.ok ? toast("Key unbound", "ok") : toast(r.error, "err");
      reloadCurrent(); break;
    }
    case "ban": {
      const m = openModal(`
        <h2>Ban key</h2>
        <form>
          <code class="muted">${esc(key)}</code>
          <label class="field"><span>Reason</span><input class="input" id="ban-reason" placeholder="key sharing, refunded…"></label>
          <label class="field"><span>Days (0 = until manually unbanned)</span><input class="input" id="ban-days" type="number" min="0" value="0"></label>
          <div class="modal-actions">
            <button type="button" class="btn btn-ghost" data-x="cancel">Cancel</button>
            <button type="submit" class="btn btn-danger">Ban key</button>
          </div>
        </form>`);
      m.querySelector('form').onsubmit = async (e) => {
        e.preventDefault();
        const days = parseInt(m.querySelector("#ban-days").value || "0", 10);
        const reason = m.querySelector("#ban-reason").value;
        closeModal();
        const r = await api("POST", "/keys/ban", { key, reason, days });
        r.ok ? toast("Key banned", "ok") : toast(r.error, "err");
        reloadCurrent();
      };
      m.querySelector('[data-x="cancel"]').onclick = closeModal;
      break;
    }
    case "extend": {
      const m = openModal(`
        <h2>Extend key</h2>
        <form>
          <code class="muted">${esc(key)}</code>
          <label class="field"><span>Days to add (counts from the later of now/expiry)</span>
            <input class="input" id="ext-days" type="number" min="0" value="30"></label>
          <label class="chk"><input type="checkbox" id="ext-perm"> Make permanent</label>
          <div class="modal-actions">
            <button type="button" class="btn btn-ghost" data-x="cancel">Cancel</button>
            <button type="submit" class="btn btn-primary">Apply</button>
          </div>
        </form>`);
      m.querySelector('form').onsubmit = async (e) => {
        e.preventDefault();
        const days = m.querySelector("#ext-perm").checked ? 0 : parseInt(m.querySelector("#ext-days").value || "0", 10);
        closeModal();
        const r = await api("POST", "/keys/extend", { key, days });
        if (r.ok) toast(`New expiry: ${r.data.expires_text}`, "ok");
        else toast(r.error, "err");
        reloadCurrent();
      };
      m.querySelector('[data-x="cancel"]').onclick = closeModal;
      break;
    }
    case "note": {
      const cur = await api("POST", "/keys/view", { key });
      const m = openModal(`
        <h2>Set internal note</h2>
        <form>
          <code class="muted">${esc(key)}</code>
          <textarea class="input" id="note-text" rows="3" placeholder="legit use, sold via DM, refund pending…">${esc(cur.ok ? (cur.data.note || "") : "")}</textarea>
          <div class="modal-actions">
            <button type="button" class="btn btn-ghost" data-x="cancel">Cancel</button>
            <button type="submit" class="btn">Save note</button>
          </div>
        </form>`);
      m.querySelector('form').onsubmit = async (e) => {
        e.preventDefault();
        const note = m.querySelector("#note-text").value;
        closeModal();
        const r = await api("POST", "/keys/set-note", { key, note });
        r.ok ? toast("Note saved", "ok") : toast(r.error, "err");
        reloadCurrent();
      };
      m.querySelector('[data-x="cancel"]').onclick = closeModal;
      break;
    }
    default: toast("Unknown action", "err");
  }
}

/* ---- generate keys modal ---- */
async function keysGenerateModal() {
  const [products, licenses] = await Promise.all([api("GET", "/products"), api("GET", "/licenses")]);
  if (!products.ok || !licenses.ok) return toast("Failed to load products/licenses", "err");

  const optProducts = products.data.map((p) =>
    `<option value="${p.id}">${esc(p.name)}${p.game_name ? ` (${esc(p.game_name)})` : ""}</option>`).join("");
  const optLicenses = licenses.data.map((l) =>
    `<option value="${l.id}">${esc(l.name)} (${l.days || "permanent"})</option>`).join("");

  const m = openModal(`
    <h2>Generate keys</h2>
    <form>
      <div class="row-2">
        <label class="field"><span>Quantity (1–500)</span>
          <input class="input" id="kg-count" type="number" min="1" max="500" value="10"></label>
        <label class="field"><span>Expiration override (days, empty = plan)</span>
          <input class="input" id="kg-days" type="number" min="0" placeholder="auto"></label>
      </div>
      <div class="row-2">
        <label class="field"><span>Product (optional)</span>
          <select class="input" id="kg-product"><option value="">—</option>${optProducts}</select></label>
        <label class="field"><span>License plan (optional)</span>
          <select class="input" id="kg-license"><option value="">—</option>${optLicenses}</select></label>
      </div>
      <label class="field"><span>Internal note (optional)</span>
        <input class="input" id="kg-note" placeholder="batch for reseller X…"></label>
      <div class="modal-actions">
        <button type="button" class="btn btn-ghost" data-x="cancel">Cancel</button>
        <button type="submit" class="btn btn-primary">Generate</button>
      </div>
    </form>`, true);
  m.querySelector('[data-x="cancel"]').onclick = closeModal;
  m.querySelector("form").onsubmit = async (e) => {
    e.preventDefault();
    const body = { count: parseInt(m.querySelector("#kg-count").value || "1", 10) };
    const days = m.querySelector("#kg-days").value.trim();
    const product = m.querySelector("#kg-product").value;
    const license = m.querySelector("#kg-license").value;
    if (days !== "") body.days = parseInt(days, 10);
    if (product) body.product_id = parseInt(product, 10);
    if (license) body.license_id = parseInt(license, 10);
    const note = m.querySelector("#kg-note").value.trim();
    if (note) body.note = note;
    const r = await api("POST", "/keys/generate", body);
    if (!r.ok) { toast(r.error, "err"); return; }
    const keys = r.data.map((k) => k.key).join("\n");
    openModal(`
      <h2>${r.data.length} keys generated</h2>
      <div class="keys-list" id="keys-out">${esc(keys)}</div>
      <div class="keys-copy">
        <button class="btn btn-primary btn-sm" id="copy-all">Copy all</button>
        <button class="btn btn-ghost btn-sm" id="regen-close">Done</button>
      </div>`, true);
    $("#copy-all").onclick = () => copyText(keys);
    $("#regen-close").onclick = () => { closeModal(); reloadCurrent(); };
  };
}

/* --------------------------------------------------------------------------
 * SCRIPTS
 * ------------------------------------------------------------------------ */
async function renderScripts() {
  const [scriptsR, productsR] = await Promise.all([api("GET", "/scripts"), api("GET", "/products")]);
  if (!scriptsR.ok) return toast(scriptsR.error, "err");
  const products = productsR.ok ? productsR.data : [];
  const isOwner = state.me?.role === "owner";

  $("#scripts-list").innerHTML = scriptsR.data.map((s) => `
    <div class="script-card" data-script="${s.id}">
      <h3>${esc(s.name)} ${s.enabled ? badge("active", "enabled") : badge("revoked", "disabled")}</h3>
      <div class="meta">
        <span>Game: <b>${esc(s.game_name || "—")}</b></span>
        <span>Product: <b>${esc(s.product_name || "—")}</b></span>
        <span class="mono">v${esc(s.current_version || "—")}</span>
        <span>${s.version_count} version${s.version_count === 1 ? "" : "s"}</span>
      </div>
      ${s.description ? `<div class="muted" style="font-size:12.5px">${esc(s.description)}</div>` : ""}
      <div class="meta">
        <span>AutoKick: <b>${s.autokick_enabled ? `on (recheck ${s.recheck_minutes}m)` : "off"}</b></span>
        <span>Updated: ${fmtDate(s.updated_at)}</span>
      </div>
      <div class="actions">
        <button class="btn btn-sm" data-act="version-publish">＋ Publish version</button>
        <button class="btn btn-ghost btn-sm" data-act="versions">Versions (${s.version_count})</button>
        <button class="btn btn-ghost btn-sm" data-act="settings">${s.enabled ? "Disable" : "Enable"}</button>
        <button class="btn btn-ghost btn-sm" data-act="edit">Edit</button>
        ${isOwner ? `<button class="btn btn-ghost btn-sm" data-act="delete">Delete</button>` : ""}
      </div>
    </div>`).join("") || `<div class="muted">No scripts yet — create the first one.</div>`;

  $("#scripts-list").onclick = async (e) => {
    const btn = e.target.closest("[data-act]");
    if (!btn) return;
    const card = btn.closest(".script-card");
    const id = parseInt(card.dataset.script, 10);
    const script = scriptsR.data.find((s) => s.id === id);
    const productsFor = products;
    switch (btn.dataset.act) {
      case "version-publish": return scriptVersionModal(script);
      case "versions": return scriptVersionsModal(script);
      case "settings": {
        const r = await api("POST", `/scripts/${id}`, { enabled: script.enabled ? false : true });
        r.ok ? toast(script.enabled ? "Script disabled" : "Script enabled", "ok") : toast(r.error, "err");
        return reloadCurrent();
      }
      case "edit": return scriptEditModal(script, productsFor);
      case "delete": {
        if (!await confirmModal("Delete script",
          "This deletes the script and ALL published versions permanently.")) return;
        const r = await api("DELETE", `/scripts/${id}`);
        r.ok ? toast("Script deleted", "ok") : toast(r.error, "err");
        return reloadCurrent();
      }
    }
  };
}

$("#script-new-btn").onclick = async () => {
  const [games, products] = await Promise.all([api("GET", "/games"), api("GET", "/products")]);
  const m = openModal(scriptFormHtml(games.ok ? games.data : [], products.ok ? products.data : []), true);
  $("#modal .btn-ghost[data-x=cancel]").onclick = closeModal;
  $("#modal form").onsubmit = async (e) => {
    e.preventDefault();
    const body = {
      name: $("#modal #sf-name").value.trim(),
      description: $("#modal #sf-desc").value || null,
      game_id: $("#modal #sf-game").value || null,
      product_id: $("#modal #sf-product").value || null,
      autokick_enabled: $("#modal #sf-autokick").checked,
      recheck_minutes: parseInt($("#modal #sf-recheck").value || "5", 10),
    };
    const source = $("#modal #sf-source").value.trim();
    if (source) {
      body.source = source;
      body.version = $("#modal #sf-version").value.trim() || "1.0.0";
      body.changelog = $("#modal #sf-changelog").value || null;
    }
    closeModal();
    const r = await api("POST", "/scripts", body);
    if (r.ok) { toast("Script created" + (source ? " with first version" : " (publish a version to deliver it)"), "ok"); reloadCurrent(); }
    else toast(r.error, "err");
  };
};

function scriptFormHtml(games, products, s = null) {
  const gOpts = games.map((g) =>
    `<option value="${g.id}" ${s?.game_id === g.id ? "selected" : ""}>${esc(g.name)}</option>`).join("");
  const pOpts = products.map((p) =>
    `<option value="${p.id}" ${s?.product_id === p.id ? "selected" : ""}>${esc(p.name)}</option>`).join("");
  return `
    <h2>${s ? "Edit script" : "New script"}</h2>
    <form>
      <div class="row-2">
        <label class="field"><span>Name</span>
          <input class="input" id="sf-name" required value="${esc(s?.name || "")}"></label>
        <label class="field"><span>Description</span>
          <input class="input" id="sf-desc" value="${esc(s?.description || "")}"></label>
      </div>
      <div class="row-2">
        <label class="field"><span>Game</span>
          <select class="input" id="sf-game"><option value="">—</option>${gOpts}</select></label>
        <label class="field"><span>Product</span>
          <select class="input" id="sf-product"><option value="">—</option>${pOpts}</select></label>
      </div>
      <div class="row-2">
        <label class="chk"><input type="checkbox" id="sf-autokick" ${(!s || s.autokick_enabled) ? "checked" : ""}>
          AutoKick revalidation (deny heartbeats when revoked)</label>
        <label class="field"><span>Recheck interval (minutes)</span>
          <input class="input" id="sf-recheck" type="number" min="1" value="${s?.recheck_minutes ?? 5}"></label>
      </div>
      ${s ? "" : `
      <label class="field"><span>First version Lua source (optional — can publish later)</span>
        <textarea class="input code" id="sf-source" rows="6" spellcheck="false" placeholder="print('Aero loaded')"></textarea></label>
      <div class="row-2">
        <label class="field"><span>Version tag</span><input class="input" id="sf-version" value="1.0.0"></label>
        <label class="field"><span>Changelog</span><input class="input" id="sf-changelog"></label>
      </div>`}
      <div class="modal-actions">
        <button type="button" class="btn btn-ghost" data-x="cancel">Cancel</button>
        <button type="submit" class="btn btn-primary">${s ? "Save" : "Create script"}</button>
      </div>
    </form>`;
}

async function scriptEditModal(script, products /*unused*/) {
  const gamesR = await api("GET", "/games");
  const productsR = await api("GET", "/products");
  const m = openModal(scriptFormHtml(gamesR.ok ? gamesR.data : [], productsR.ok ? productsR.data : [], script), true);
  m.querySelector('[data-x="cancel"]').onclick = closeModal;
  m.querySelector("form").onsubmit = async (e) => {
    e.preventDefault();
    const body = {
      name: m.querySelector("#sf-name").value.trim(),
      description: m.querySelector("#sf-desc").value || null,
      game_id: m.querySelector("#sf-game").value || null,
      product_id: m.querySelector("#sf-product").value || null,
      autokick_enabled: m.querySelector("#sf-autokick").checked,
      recheck_minutes: parseInt(m.querySelector("#sf-recheck").value || "5", 10),
    };
    closeModal();
    const r = await api("POST", `/scripts/${script.id}`, body);
    r.ok ? (toast("Script saved", "ok"), reloadCurrent()) : toast(r.error, "err");
  };
}

async function scriptVersionModal(script) {
  const m = openModal(`
    <h2>Publish version — ${esc(script.name)}</h2>
    <form>
      <div class="row-2">
        <label class="field"><span>Version tag</span>
          <input class="input" id="sv-version" required placeholder="1.3.0"></label>
        <label class="field"><span>Changelog</span>
          <input class="input" id="sv-changelog" placeholder="what changed"></label>
      </div>
      <label class="field"><span>Lua source (replaces delivery for every active key)</span>
        <textarea class="input code" id="sv-source" rows="10" spellcheck="false" required></textarea></label>
      <div class="hint">⚠ Publishing makes this the <b>live</b> version immediately. Old versions remain in history.</div>
      <div class="modal-actions">
        <button type="button" class="btn btn-ghost" data-x="cancel">Cancel</button>
        <button type="submit" class="btn btn-primary">Publish</button>
      </div>
    </form>`, true);
  m.querySelector('[data-x="cancel"]').onclick = closeModal;
  m.querySelector("form").onsubmit = async (e) => {
    e.preventDefault();
    const body = {
      version: m.querySelector("#sv-version").value.trim(),
      source: m.querySelector("#sv-source").value,
      changelog: m.querySelector("#sv-changelog").value || null,
    };
    closeModal();
    const r = await api("POST", `/scripts/${script.id}/versions`, body);
    r.ok ? (toast(`Version ${r.data.version} published → live`, "ok"), reloadCurrent())
         : toast(r.error, "err");
  };
}

async function scriptVersionsModal(script) {
  const r = await api("GET", `/scripts/${script.id}/versions`);
  if (!r.ok) return toast(r.error, "err");
  const vs = r.data;
  const rows = vs.map((v, idx) => `
    <tr data-vid="${v.id}">
      <td class="mono">${esc(v.version)}${idx === 0 ? badge("active", "live") : ""}</td>
      <td>${fmtDate(v.created_at)}</td>
      <td>${(v.source_size / 1024).toFixed(1)} KB</td>
      <td title="${esc(v.changelog || "")}">${esc(v.changelog || "—")}</td>
      <td>
        <button class="btn btn-ghost btn-sm" data-act="view">View</button>
        ${idx === 0 ? "" : `<button class="btn btn-ghost btn-sm" data-act="del">Delete</button>`}
      </td>
    </tr>`).join("");
  const m = openModal(`
    <h2>Versions — ${esc(script.name)}</h2>
    <table class="table"><thead><tr><th>Version</th><th>Date</th><th>Size</th><th>Changelog</th><th></th></tr></thead>
      <tbody>${rows || `<tr><td colspan="5" class="muted">No versions published</td></tr>`}</tbody></table>
    <div class="modal-actions"><button class="btn" data-x="close">Close</button></div>`, true);
  m.querySelector('[data-x="close"]').onclick = closeModal;
  m.querySelector("table").onclick = async (e) => {
    const act = e.target.closest("[data-act]")?.dataset.act;
    if (!act) return;
    const vid = parseInt(e.target.closest("tr[data-vid]").dataset.vid, 10);
    if (act === "view") {
      const vr = await api("GET", `/versions/${vid}`);
      if (!vr.ok) return toast(vr.error, "err");
      const mv = openModal(`
        <h2>${esc(vr.data.version)} — source</h2>
        <pre>${esc(vr.data.source)}</pre>
        <div class="keys-copy">
          <button class="btn btn-sm" id="src-copy">Copy source</button>
          <button class="btn btn-ghost btn-sm" data-x="close">Back</button>
        </div>`, true);
      $("#src-copy").onclick = () => copyText(vr.data.source);
      mv.querySelector('[data-x="close"]').onclick = closeModal;
      return;
    }
    if (act === "del") {
      if (!await confirmModal("Delete version", "Delete this historical version permanently?")) return;
      const dr = await api("DELETE", `/versions/${vid}`);
      dr.ok ? (toast("Version deleted", "ok"), closeModal(), renderScripts()) : toast(dr.error, "err");
    }
  };
}

/* --------------------------------------------------------------------------
 * CATALOG (games/licenses/products)
 * ------------------------------------------------------------------------ */
async function renderCatalog() {
  const [g, l, p] = await Promise.all([api("GET", "/games"), api("GET", "/licenses"), api("GET", "/products")]);
  $("#games-table tbody").innerHTML = g.ok ? (g.data.map((x) => `
    <tr data-id="${x.id}">
      <td>${esc(x.name)}</td>
      <td class="mono">${esc(x.place_ids || "—")}</td>
      <td>${x.active ? badge("active", "active") : badge("revoked", "inactive")}</td>
      <td><button class="btn btn-ghost btn-sm" data-act="game-edit">Edit</button></td>
    </tr>`).join("")) : `<tr><td colspan="4" class="muted">${esc(g.error)}</td></tr>`;

  $("#licenses-table tbody").innerHTML = l.ok ? (l.data.map((x) => `
    <tr>
      <td>${esc(x.name)}</td>
      <td>${x.days ? x.days + " days" : badge("active", "Permanent")}</td>
      <td>${fmtMoney(x.price_cents)}</td>
      <td></td>
    </tr>`).join("")) : `<tr><td colspan="4" class="muted">${esc(l.error)}</td></tr>`;

  $("#products-table tbody").innerHTML = p.ok ? (p.data.map((x) => `
    <tr data-id="${x.id}">
      <td>${esc(x.name)}</td>
      <td>${esc(x.game_name || "—")}</td>
      <td>${esc(x.license_name || "—")}</td>
      <td>${fmtMoney(x.price_cents)}</td>
      <td><button class="btn btn-ghost btn-sm" data-act="product-edit">Edit</button></td>
    </tr>`).join("")) : `<tr><td colspan="5" class="muted">${esc(p.error)}</td></tr>`;

  $("#games-table tbody").onclick = (e) => {
    if (e.target.closest("[data-act='game-edit']"))
      gameModal(parseInt(e.target.closest("tr[data-id]").dataset.id, 10));
  };
  $("#products-table tbody").onclick = (e) => {
    if (e.target.closest("[data-act='product-edit']"))
      productModal(parseInt(e.target.closest("tr[data-id]").dataset.id, 10));
  };
}

$("#game-new-btn").onclick = () => gameModal(null);
async function gameModal(gameId) {
  let g = null;
  if (gameId) {
    const r = await api("GET", "/games");
    if (!r.ok) return toast(r.error, "err");
    g = r.data.find((x) => x.id === gameId);
    if (!g) return toast("Game not found", "err");
  }
  const m = openModal(`
    <h2>${g ? "Edit game" : "New game"}</h2>
    <form>
      <label class="field"><span>Name</span>
        <input class="input" id="gm-name" required value="${esc(g?.name || "")}"></label>
      <label class="field"><span>Roblox Place IDs (comma-separated)</span>
        <input class="input" id="gm-places" placeholder="2753915549, 9999999999" value="${esc(g?.place_ids || "")}"></label>
      <label class="chk"><input type="checkbox" id="gm-active" ${!g || g.active ? "checked" : ""}> Active</label>
      ${gameId ? `<div class="modal-actions"><button type="button" class="btn btn-danger" data-x="del">Delete game</button></div>` : ""}
      <div class="modal-actions">
        <button type="button" class="btn btn-ghost" data-x="cancel">Cancel</button>
        <button type="submit" class="btn btn-primary">Save</button>
      </div>
    </form>`);
  m.querySelector('[data-x="cancel"]').onclick = closeModal;
  const delBtn = m.querySelector('[data-x="del"]');
  if (delBtn) delBtn.onclick = async () => {
    if (!await confirmModal("Delete game", `Remove "${g.name}" from the catalog?`)) return;
    closeModal();
    const r = await api("DELETE", `/games/${gameId}`);
    r.ok ? (toast("Game deleted", "ok"), reloadCurrent()) : toast(r.error, "err");
  };
  m.querySelector("form").onsubmit = async (e) => {
    e.preventDefault();
    const body = {
      name: m.querySelector("#gm-name").value.trim(),
      place_ids: m.querySelector("#gm-places").value,
      active: m.querySelector("#gm-active").checked ? 1 : 0,
    };
    closeModal();
    const r = gameId ? await api("POST", `/games/${gameId}`, body)
                     : await api("POST", "/games", body);
    r.ok ? (toast(gameId ? "Game saved" : "Game created", "ok"), reloadCurrent())
         : toast(r.error, "err");
  };
}

$("#license-new-btn").onclick = () => {
  const m = openModal(`
    <h2>New license plan</h2>
    <form>
      <label class="field"><span>Name</span><input class="input" id="lc-name" required placeholder="Monthly / Lifetime"></label>
      <div class="row-2">
        <label class="field"><span>Duration (days, 0 = permanent)</span>
          <input class="input" id="lc-days" type="number" min="0" value="30"></label>
        <label class="field"><span>Price (cents, optional)</span>
          <input class="input" id="lc-price" type="number" min="0" value="499"></label>
      </div>
      <div class="modal-actions">
        <button type="button" class="btn btn-ghost" data-x="cancel">Cancel</button>
        <button type="submit" class="btn btn-primary">Create</button>
      </div>
    </form>`);
  m.querySelector('[data-x="cancel"]').onclick = closeModal;
  m.querySelector("form").onsubmit = async (e) => {
    e.preventDefault();
    const body = {
      name: m.querySelector("#lc-name").value.trim(),
      days: parseInt(m.querySelector("#lc-days").value || "0", 10),
    };
    const price = m.querySelector("#lc-price").value;
    if (price !== "") body.price_cents = parseInt(price, 10);
    closeModal();
    const r = await api("POST", "/licenses", body);
    r.ok ? (toast("License created", "ok"), reloadCurrent()) : toast(r.error, "err");
  };
};

$("#product-new-btn").onclick = () => productModal(null);
async function productModal(productId) {
  const [g, l] = await Promise.all([api("GET", "/games"), api("GET", "/licenses")]);
  let p = null;
  if (productId) {
    const r = await api("GET", "/products");
    if (!r.ok) return toast(r.error, "err");
    p = r.data.find((x) => x.id === productId);
  }
  const games = g.ok ? g.data : [];
  const lics = l.ok ? l.data : [];
  const m = openModal(`
    <h2>${p ? "Edit product" : "New product"}</h2>
    <form>
      <label class="field"><span>Name</span><input class="input" id="pr-name" required value="${esc(p?.name || "")}"></label>
      <label class="field"><span>Description</span><input class="input" id="pr-desc" value="${esc(p?.description || "")}"></label>
      <div class="row-2">
        <label class="field"><span>Game</span>
          <select class="input" id="pr-game"><option value="">—</option>
            ${games.map((x) => `<option value="${x.id}" ${p?.game_id === x.id ? "selected" : ""}>${esc(x.name)}</option>`).join("")}
          </select></label>
        <label class="field"><span>License plan</span>
          <select class="input" id="pr-license"><option value="">—</option>
            ${lics.map((x) => `<option value="${x.id}" ${p?.license_id === x.id ? "selected" : ""}>${esc(x.name)}</option>`).join("")}
          </select></label>
      </div>
      <div class="row-2">
        <label class="field"><span>Price (cents)</span>
          <input class="input" id="pr-price" type="number" min="0" value="${p?.price_cents ?? ""}"></label>
        <label class="chk" style="align-self:end"><input type="checkbox" id="pr-active" ${!p || p.active ? "checked" : ""}> Active</label>
      </div>
      ${productId ? `<div class="modal-actions"><button type="button" class="btn btn-danger" data-x="del">Delete product</button></div>` : ""}
      <div class="modal-actions">
        <button type="button" class="btn btn-ghost" data-x="cancel">Cancel</button>
        <button type="submit" class="btn btn-primary">Save</button>
      </div>
    </form>`);
  m.querySelector('[data-x="cancel"]').onclick = closeModal;
  const delBtn = m.querySelector('[data-x="del"]');
  if (delBtn) delBtn.onclick = async () => {
    if (!await confirmModal("Delete product", `Remove "${p.name}"? Existing keys keep working with what they were issued against.`)) return;
    closeModal();
    const r = await api("DELETE", `/products/${productId}`);
    r.ok ? (toast("Product deleted", "ok"), reloadCurrent()) : toast(r.error, "err");
  };
  m.querySelector("form").onsubmit = async (e) => {
    e.preventDefault();
    const body = {
      name: m.querySelector("#pr-name").value.trim(),
      description: m.querySelector("#pr-desc").value || null,
      game_id: m.querySelector("#pr-game").value ? parseInt(m.querySelector("#pr-game").value, 10) : null,
      license_id: m.querySelector("#pr-license").value ? parseInt(m.querySelector("#pr-license").value, 10) : null,
      price_cents: m.querySelector("#pr-price").value === "" ? null : parseInt(m.querySelector("#pr-price").value, 10),
      active: m.querySelector("#pr-active").checked ? 1 : 0,
    };
    closeModal();
    const r = productId ? await api("POST", `/products/${productId}`, body)
                        : await api("POST", "/products", body);
    r.ok ? (toast(productId ? "Product saved" : "Product created", "ok"), reloadCurrent())
         : toast(r.error, "err");
  };
}

/* --------------------------------------------------------------------------
 * USERS
 * ------------------------------------------------------------------------ */
const USERS_PER_PAGE = 25;

async function renderUsers() {
  const q = new URLSearchParams({ limit: USERS_PER_PAGE, offset: state.usersPage * USERS_PER_PAGE });
  if (state.usersSearch) q.set("search", state.usersSearch);
  const r = await api("GET", `/users?${q}`);
  if (!r.ok) return toast(r.error, "err");
  const { rows, total } = r.data;
  $("#users-total").textContent = `${total} user${total === 1 ? "" : "s"}`;
  $("#users-table tbody").innerHTML = rows.map((u) => `
    <tr data-id="${u.id}" data-disc="${u.discord_id ?? ""}" data-notes="${esc(u.notes || "")}">
      <td class="mono">${u.discord_id ? esc(String(u.discord_id)) : "—"}</td>
      <td>${esc(u.display_name || "—")}</td>
      <td>${u.total_keys ?? 0}</td>
      <td>${u.active_keys ?? 0}</td>
      <td>${u.role !== "buyer" ? badge("service", u.role) : ""}
          ${u.banned ? badge("revoked", "banned") : badge("active", "ok")}</td>
      <td>${fmtDate(u.created_at)}</td>
      <td>
        <div style="display:flex;gap:5px">
          <button class="btn btn-ghost btn-sm" data-act="view">Open</button>
          ${u.banned ? "" : `<button class="btn btn-ghost btn-sm" data-act="ban">Ban</button>`}
          ${u.discord_id ? `<button class="btn btn-ghost btn-sm" data-act="grant" data-role="${u.role === "buyer" ? "staff" : "buyer"}">→ ${u.role === "buyer" ? "staff" : "buyer"}</button>` : ""}
        </div>
      </td>
    </tr>`).join("") || `<tr><td colspan="7" class="muted">No users found</td></tr>`;

  $("#users-table tbody").onclick = (e) => {
    const btn = e.target.closest("[data-act]");
    if (!btn) return;
    const row = btn.closest("tr[data-id]");
    const id = parseInt(row.dataset.id, 10);
    const discordId = row.dataset.disc ? parseInt(row.dataset.disc, 10) : null;
    if (btn.dataset.act === "view") return userDetail(id);
    if (btn.dataset.act === "ban") return userBanModal(discordId, row.dataset.notes);
    if (btn.dataset.act === "grant") {
      const role = btn.dataset.role;
      return (async () => {
        const r = await api("POST", "/users/grant", { user_id: id, role });
        r.ok ? (toast(`Role set to ${role}`, "ok"), reloadCurrent()) : toast(r.error, "err");
      })();
    }
  };
}

$("#users-search").addEventListener("input", debounce(() => {
  state.usersSearch = $("#users-search").value.trim();
  state.usersPage = 0;
  renderUsers();
}, 300));
$("#users-prev").onclick = () => { if (state.usersPage > 0) { state.usersPage--; renderUsers(); } };
$("#users-next").onclick = () => { state.usersPage++; renderUsers(); };
$("#user-detail-close").onclick = () => {
  $("#user-detail-card").hidden = true;
};
$("#user-notes-save").onclick = async () => {
  const id = parseInt($("#user-detail-card").dataset.uid, 10);
  const r = await api("POST", "/users/notes", { user_id: id, notes: $("#user-notes").value });
  r.ok ? toast("Notes saved", "ok") : toast(r.error, "err");
};

async function userDetail(uid) {
  const r = await api("GET", `/users/${uid}`);
  if (!r.ok) return toast(r.error, "err");
  const { user, keys, events } = r.data;
  const card = $("#user-detail-card");
  card.hidden = false;
  card.dataset.uid = uid;
  $("#user-detail-title").textContent =
    `${user.display_name || "user"} ${user.discord_id ? "· " + user.discord_id : ""}`;
  $("#user-notes").value = user.notes || "";
  $("#user-key-table tbody").innerHTML = keys.map((k) => `
    <tr>
      <td class="mono">${esc(k.key.slice(0, 14) + "…")}</td>
      <td>${badge(k.status, STATUS_LABEL[k.status] || k.status)}</td>
      <td>${k.expires_at ? fmtDate(k.expires_at) : badge("active", "Permanent")}</td>
      <td>${k.executions}</td>
    </tr>`).join("") || `<tr><td colspan="4" class="muted">No keys</td></tr>`;
  $("#user-event-table tbody").innerHTML = events.slice(0, 30).map((ev) => `
    <tr>
      <td>${fmtTime(ev.ts)}</td>
      <td>${esc(ev.kind)}</td>
      <td>${ev.result ? badge(ev.result === "ok" ? "ok" : "denied", ev.result) : "—"}</td>
      <td title="${esc(ev.reason || "")}">${esc(ev.reason || "—")}</td>
    </tr>`).join("") || `<tr><td colspan="4" class="muted">No access history</td></tr>`;
  card.scrollIntoView({ behavior: "smooth", block: "start" });
}

function userBanModal(discordId) {
  if (!discordId) return toast("User has no Discord ID", "err");
  const m = openModal(`
    <h2>Ban Discord user</h2>
    <form>
      <code class="muted">${esc(String(discordId))}</code>
      <label class="field"><span>Reason</span><input class="input" id="ub-reason" placeholder="chargeback, scam…"></label>
      <label class="field"><span>Days (0 = until manual unban)</span>
        <input class="input" id="ub-days" type="number" min="0" value="0"></label>
      <div class="hint">Bans the user and every key bound to them (loader denies instantly).</div>
      <div class="modal-actions">
        <button type="button" class="btn btn-ghost" data-x="cancel">Cancel</button>
        <button type="submit" class="btn btn-danger">Ban user</button>
      </div>
    </form>`);
  m.querySelector('[data-x="cancel"]').onclick = closeModal;
  m.querySelector("form").onsubmit = async (e) => {
    e.preventDefault();
    const body = {
      discord_id: String(discordId),
      reason: m.querySelector("#ub-reason").value,
      days: parseInt(m.querySelector("#ub-days").value || "0", 10),
    };
    closeModal();
    const r = await api("POST", "/users/ban", body);
    r.ok ? (toast("User banned", "ok"), reloadCurrent()) : toast(r.error, "err");
  };
}

/* --------------------------------------------------------------------------
 * SALES
 * ------------------------------------------------------------------------ */
async function renderSales() {
  const [salesR, overR] = await Promise.all([api("GET", "/sales"), api("GET", "/overview")]);
  if (!salesR.ok) return toast(salesR.error, "err");
  const o = overR.ok ? overR.data : null;
  $("#sales-totals").innerHTML = o ? `
    All-time: <b>${fmtMoney(o.sales?.revenue_total_cents ?? 0)}</b> ·
    Last 30 days: <b>${fmtMoney(o.sales?.revenue_30d_cents ?? 0)}</b> ·
    ${o.sales?.count ?? 0} sales`
    : "";
  $("#sales-table tbody").innerHTML = salesR.data.map((s) => `
    <tr>
      <td>${fmtDate(s.created_at)}</td>
      <td>${esc(s.buyer)}</td>
      <td class="mono">${esc(s.discord_id || "—")}</td>
      <td>${esc(s.game || "—")}</td>
      <td>${esc(s.product || "—")}</td>
      <td>${fmtMoney(s.amount_cents)}</td>
      <td>${badge(s.status === "paid" ? "active" : "neutral", s.status)}</td>
    </tr>`).join("") || `<tr><td colspan="7" class="muted">No sales recorded yet</td></tr>`;
}

$("#sale-new-btn").onclick = () => {
  const m = openModal(`
    <h2>Record sale</h2>
    <form>
      <div class="row-2">
        <label class="field"><span>Buyer (Discord name)</span>
          <input class="input" id="sl-buyer" required></label>
        <label class="field"><span>Discord ID (optional)</span>
          <input class="input" id="sl-disc"></label>
      </div>
      <div class="row-2">
        <label class="field"><span>Game</span><input class="input" id="sl-game" placeholder="Deepwoken"></label>
        <label class="field"><span>Product</span><input class="input" id="sl-product" placeholder="Aero Weekly"></label>
      </div>
      <div class="row-2">
        <label class="field"><span>Amount (cents)</span>
          <input class="input" id="sl-amount" type="number" min="0" value="499"></label>
        <label class="field"><span>Status</span>
          <select class="input" id="sl-status">
            <option value="paid">paid</option><option value="pending">pending</option><option value="refunded">refunded</option>
          </select></label>
      </div>
      <label class="field"><span>Note</span><input class="input" id="sl-note"></label>
      <div class="modal-actions">
        <button type="button" class="btn btn-ghost" data-x="cancel">Cancel</button>
        <button type="submit" class="btn btn-primary">Record</button>
      </div>
    </form>`);
  m.querySelector('[data-x="cancel"]').onclick = closeModal;
  m.querySelector("form").onsubmit = async (e) => {
    e.preventDefault();
    const body = {
      buyer: m.querySelector("#sl-buyer").value.trim(),
      discord_id: m.querySelector("#sl-disc").value.trim() || null,
      game: m.querySelector("#sl-game").value.trim() || null,
      product: m.querySelector("#sl-product").value.trim() || null,
      amount_cents: parseInt(m.querySelector("#sl-amount").value || "0", 10),
      status: m.querySelector("#sl-status").value,
      note: m.querySelector("#sl-note").value || null,
    };
    closeModal();
    const r = await api("POST", "/sales", body);
    r.ok ? (toast("Sale recorded", "ok"), reloadCurrent()) : toast(r.error, "err");
  };
};

/* --------------------------------------------------------------------------
 * ACTIVITY
 * ------------------------------------------------------------------------ */
async function renderActivity() {
  state.evKind = $("#ev-kind").value;
  const q = state.evKind ? `?kind=${encodeURIComponent(state.evKind)}&limit=100` : "?limit=100";
  const [evR, auR] = await Promise.all([api("GET", `/events${q}`), api("GET", "/audit?limit=100")]);
  $("#events-table tbody").innerHTML = evR.ok ? evR.data.map((e) => `
    <tr>
      <td>${fmtTime(e.ts)}</td>
      <td>${esc(e.kind)}</td>
      <td>${e.result ? badge(e.result === "ok" ? "ok" : "denied", e.result) : badge("neutral", "—")}</td>
      <td class="mono">${esc(e.key ? e.key.slice(0, 12) + "…" : "—")}</td>
      <td class="mono">${esc(e.hwid || "—")}</td>
      <td class="mono">${esc(e.ip || "—")}</td>
      <td title="${esc(e.reason || e.detail || "")}">${esc(e.reason || e.detail || "—")}</td>
    </tr>`).join("") : `<tr><td colspan="7" class="muted">${esc(evR.error)}</td></tr>`;

  $("#audit-table tbody").innerHTML = auR.ok ? auR.data.map((a) => `
    <tr>
      <td>${fmtTime(a.ts)}</td>
      <td>${esc(a.actor || "—")}</td>
      <td>${esc(a.action)}</td>
      <td>${esc(a.target || "—")}</td>
      <td>${esc(a.detail || "—")}</td>
    </tr>`).join("") : `<tr><td colspan="5" class="muted">${esc(auR.error)}</td></tr>`;
}
$("#ev-kind").addEventListener("change", renderActivity);
$("#ev-reload").onclick = renderActivity;

/* --------------------------------------------------------------------------
 * SETTINGS
 * ------------------------------------------------------------------------ */
async function renderSettings() {
  // health
  try {
    const r = await fetch("/v1/health");
    const h = await r.json();
    $("#api-status").className = `api-status ${r.ok ? "ok" : "down"}`;
    $("#api-status").textContent = r.ok
      ? `API online · v${h.version} · up ${humanUptime(h.uptime)}`
      : "API health check failed";
  } catch {
    $("#api-status").className = "api-status down";
    $("#api-status").textContent = "API unreachable";
  }
  const pub = location.origin;
  $("#loader-url").textContent = `${pub}/loader/aero_loader.lua`;
  $("#health-url").textContent = `${pub}/v1/health`;
  $$("[data-copy]").forEach((b) => b.onclick = () => copyText($("#" + b.dataset.copy).textContent));

  const [tokensR, dashUsersR] = await Promise.all([api("GET", "/tokens"), api("GET", "/dashboard-users")]);
  $("#tokens-table tbody").innerHTML = tokensR.ok ? tokensR.data.map((t) => `
    <tr>
      <td>${esc(t.name)}</td>
      <td>${badge(t.role, t.role)}</td>
      <td class="mono">${esc(t.token_prefix)}…</td>
      <td>${t.last_used ? fmtDate(t.last_used) : "never"}</td>
      <td>${t.revoked ? badge("revoked", "revoked") : badge("active", "active")}</td>
      <td>${t.revoked ? "" : `<button class="btn btn-ghost btn-sm" data-tid="${t.id}" data-act="trev">Revoke</button>`}</td>
    </tr>`).join("") : `<tr><td colspan="6" class="muted">Owner account required to manage tokens${tokensR.ok ? "" : " — " + esc(tokensR.error)}</td></tr>`;

  $("#dash-users-table tbody").innerHTML = dashUsersR.ok ? dashUsersR.data.map((u) => `
    <tr>
      <td>${esc(u.email)}${u.must_change ? badge("expired", "password pending") : ""}</td>
      <td>${badge(u.role === "owner" ? "active" : "service", u.role)}</td>
      <td>${u.last_login ? fmtDate(u.last_login) : "never"}</td>
      <td>${badge("active", "ok")}</td>
    </tr>`).join("") : `<tr><td colspan="4" class="muted">Owner account required${dashUsersR.ok ? "" : " — " + esc(dashUsersR.error)}</td></tr>`;

  $("#tokens-table").onclick = async (e) => {
    const btn = e.target.closest("[data-act='trev']");
    if (!btn) return;
    if (!await confirmModal("Revoke token", "The bot or service using this token loses API access immediately.")) return;
    const r = await api("POST", `/tokens/${btn.dataset.tid}/revoke`);
    r.ok ? (toast("Token revoked", "ok"), renderSettings()) : toast(r.error, "err");
  };
}

$("#token-new-btn").onclick = () => {
  const m = openModal(`
    <h2>Create API token</h2>
    <form>
      <label class="field"><span>Name (what uses it)</span>
        <input class="input" id="tk-name" required placeholder="discord-bot"></label>
      <label class="field"><span>Role</span>
        <select class="input" id="tk-role">
          <option value="service">service — full dashboard API (Discord bot)</option>
          <option value="loader">loader — delivery-only, cannot touch this API</option>
        </select></label>
      <div class="hint">The token is shown once after creation — store it in the bot's <code>.env</code>.</div>
      <div class="modal-actions">
        <button type="button" class="btn btn-ghost" data-x="cancel">Cancel</button>
        <button type="submit" class="btn btn-primary">Create token</button>
      </div>
    </form>`);
  m.querySelector('[data-x="cancel"]').onclick = closeModal;
  m.querySelector("form").onsubmit = async (e) => {
    e.preventDefault();
    const body = {
      name: m.querySelector("#tk-name").value.trim(),
      role: m.querySelector("#tk-role").value,
    };
    closeModal();
    const r = await api("POST", "/tokens", body);
    if (!r.ok) return toast(r.error, "err");
    const m2 = openModal(`
      <h2>Token created — copy it NOW</h2>
      <div class="keys-list" id="new-token" style="user-select:all">${esc(r.data.token)}</div>
      <div class="keys-copy">
        <button class="btn btn-primary btn-sm" id="tk-copy">Copy token</button>
        <button class="btn btn-ghost btn-sm" data-x="close">Done</button>
      </div>`);
    $("#tk-copy").onclick = () => copyText(r.data.token);
    m2.querySelector('[data-x="close"]').onclick = () => { closeModal(); renderSettings(); };
  };
};

$("#dash-user-new-btn").onclick = () => {
  if (state.me?.role !== "owner") return toast("Owner required", "err");
  const m = openModal(`
    <h2>New dashboard account</h2>
    <form>
      <label class="field"><span>Email</span><input class="input" id="du-email" type="email" required></label>
      <label class="field"><span>Password (min 8 chars, must change on first login)</span>
        <input class="input" id="du-pass" type="text" required minlength="8"></label>
      <label class="field"><span>Role</span>
        <select class="input" id="du-role"><option value="staff">staff (no deletes/tokens)</option><option value="owner">owner</option></select></label>
      <div class="modal-actions">
        <button type="button" class="btn btn-ghost" data-x="cancel">Cancel</button>
        <button type="submit" class="btn btn-primary">Create</button>
      </div>
    </form>`);
  m.querySelector('[data-x="cancel"]').onclick = closeModal;
  m.querySelector("form").onsubmit = async (e) => {
    e.preventDefault();
    const body = {
      email: m.querySelector("#du-email").value.trim(),
      password: m.querySelector("#du-pass").value,
      role: m.querySelector("#du-role").value,
    };
    closeModal();
    const r = await api("POST", "/dashboard-users", body);
    r.ok ? (toast("Account created", "ok"), renderSettings()) : toast(r.error, "err");
  };
};

$("#pw-save").onclick = async () => {
  const old = $("#pw-old").value;
  const nw = $("#pw-new").value;
  if (nw.length < 8) return toast("New password needs 8+ characters", "err");
  const r = await api("POST", "/change-password", { old, new: nw });
  if (r.ok) {
    toast("Password updated", "ok");
    $("#pw-old").value = $("#pw-new").value = "";
    await loadMe();
    applyWhoami();
  } else toast(r.error, "err");
};

/* --------------------------------------------------------------------------
 * boot
 * ------------------------------------------------------------------------ */
(async function boot() {
  if (await loadMe()) showApp();
  else showLogin();
  // re-check who am I after each reload (session expiry)
  document.addEventListener("visibilitychange", async () => {
    if (!document.hidden && !$("#app-view").hidden && !(await loadMe())) showLogin();
  });
})();
