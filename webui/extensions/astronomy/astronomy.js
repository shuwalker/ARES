/**
 * ARES Astronomy — Telescope control, star map, and night planning.
 *
 * Registers as a sidebar tab via the WebUI extension slot system.
 * Fetches equipment status and night info from /api/astronomy/ endpoints.
 * Real device interaction is proxied through the INDI-bridge sidecar.
 */
(() => {
  "use strict";

  /* ── Guard against double-injection ── */
  if (document.getElementById("astronomy-root")) return;

  /* ── Extension settings (browser-local) ── */
  const SETTINGS = (() => {
    try {
      const s = window.AresExtensionSettings?.settingsForExtension?.("astronomy");
      if (s) return s;
    } catch (_) { /* fallback */ }
    return {
      get(key) { try { return JSON.parse(localStorage.getItem(`ares:ext:astronomy:${key}`)); } catch { return undefined; } },
      set(key, val) { try { localStorage.setItem(`ares:ext:astronomy:${key}`, JSON.stringify(val)); } catch { /* */ } },
    };
  })();

  /* ── State ── */
  const state = {
    status: null,    // /api/astronomy/status response
    nightInfo: null, // /api/astronomy/night-info response
    targets: [],     // /api/astronomy/targets response
    loading: true,
    error: null,
    devices: {},     // id -> { connecting: bool }
  };

  /* ── API helpers ── */
  async function apiFetch(path, opts = {}) {
    const res = await fetch(path, { credentials: "same-origin", ...opts });
    if (!res.ok) {
      const body = await res.text().catch(() => "");
      throw new Error(`${res.status} ${res.statusText}${body ? ": " + body.slice(0, 200) : ""}`);
    }
    return res.json();
  }

  async function loadStatus() {
    try {
      state.status = await apiFetch("/api/astronomy/status");
    } catch (e) {
      /* Status endpoint may not be running yet — fall back to empty */
      state.status = { devices: [] };
    }
  }

  async function loadNightInfo() {
    try {
      state.nightInfo = await apiFetch("/api/astronomy/night-info");
    } catch (e) {
      state.nightInfo = null;
    }
  }

  async function loadTargets() {
    try {
      const data = await apiFetch("/api/astronomy/targets");
      state.targets = data.targets || [];
    } catch (e) {
      state.targets = [];
    }
  }

  /* ── Connect / disconnect ── */
  async function toggleDevice(deviceId, currentlyConnected) {
    state.devices[deviceId] = state.devices[deviceId] || {};
    state.devices[deviceId].connecting = true;
    render();

    const endpoint = currentlyConnected ? "disconnect" : "connect";
    try {
      await apiFetch(`/api/astronomy/${endpoint}/${encodeURIComponent(deviceId)}`, { method: "POST" });
      await loadStatus();
    } catch (e) {
      state.error = `Failed to ${endpoint} ${deviceId}: ${e.message}`;
    } finally {
      if (state.devices[deviceId]) state.devices[deviceId].connecting = false;
      render();
    }
  }

  /* ── DOM helpers ── */
  function el(tag, cls, ...children) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    for (const c of children) {
      if (typeof c === "string") e.appendChild(document.createTextNode(c));
      else if (c) e.appendChild(c);
    }
    return e;
  }

  /* ── Connection dot ── */
  function connDot(connected) {
    const dot = el("span", `astronomy-conn-dot ${connected ? "connected" : "disconnected"}`);
    dot.title = connected ? "Connected" : "Disconnected";
    return dot;
  }

  /* ── Equipment card ── */
  function equipmentCard(device) {
    const id = device.id || device.name || "unknown";
    const connected = !!device.connected;
    const connecting = state.devices[id]?.connecting;
    const card = el("div", "astronomy-card");

    /* Header */
    const header = el("div", "astronomy-card-header");
    header.appendChild(connDot(connected));
    header.appendChild(el("span", "astronomy-card-label", device.label || device.name || id));
    header.appendChild(el("span", "astronomy-card-type", device.type || "device"));
    card.appendChild(header);

    /* Details */
    const details = el("div", "astronomy-card-details");
    if (device.ra != null) details.appendChild(detailRow("RA", device.ra));
    if (device.dec != null) details.appendChild(detailRow("Dec", device.dec));
    if (device.alt != null) details.appendChild(detailRow("Alt", `${device.alt}°`));
    if (device.az != null) details.appendChild(detailRow("Az", `${device.az}°`));
    if (device.temperature != null) details.appendChild(detailRow("Temp", `${device.temperature}°C`));
    if (device.exposure != null) details.appendChild(detailRow("Exposure", device.exposure));
    if (device.filter != null) details.appendChild(detailRow("Filter", device.filter));
    if (device.focus_position != null) details.appendChild(detailRow("Focus", device.focus_position));
    if (details.children.length) card.appendChild(details);

    /* Connect / Disconnect button */
    const btn = el("button",
      `astronomy-btn ${connected ? "astronomy-btn--danger" : ""}`,
      connecting ? "…" : (connected ? "Disconnect" : "Connect"));
    btn.disabled = !!connecting;
    btn.addEventListener("click", () => toggleDevice(id, connected));
    card.appendChild(btn);

    return card;
  }

  function detailRow(label, value) {
    const row = el("div", "astronomy-card-detail-row");
    row.appendChild(el("span", "astronomy-card-detail-label", label));
    row.appendChild(el("span", "astronomy-card-detail-value", String(value)));
    return row;
  }

  /* ── Moon phase emoji ── */
  function moonEmoji(phase) {
    if (phase == null) return "🌕";
    if (phase < 0.06 || phase >= 0.94) return "🌕";
    if (phase < 0.19) return "🌖";
    if (phase < 0.31) return "🌗";
    if (phase < 0.44) return "🌘";
    if (phase < 0.56) return "🌑";
    if (phase < 0.69) return "🌒";
    if (phase < 0.81) return "🌓";
    return "🌔";
  }

  /* ── Night planning panel ── */
  function nightPanel() {
    const panel = el("div", "astronomy-night-panel");
    const ni = state.nightInfo;

    if (!ni) {
      panel.appendChild(el("div", "astronomy-error-banner",
        "⚠ Night info unavailable — check that the astronomy service is running."));
      return panel;
    }

    /* Header */
    const header = el("div", "astronomy-night-header");
    header.appendChild(el("div", "astronomy-section-title", "🔭 Night Planning"));
    if (ni.location) {
      header.appendChild(el("div", "astronomy-night-location", ni.location));
    }
    panel.appendChild(header);

    /* Twilight timeline */
    if (ni.twilight) {
      const tw = ni.twilight;
      const timeline = el("div", "astronomy-timeline");
      const nightStart = tw.astro_twilight_end || tw.nautical_twilight_end || tw.sunset;
      const nightEnd = tw.astro_twilight_begin || tw.nautical_twilight_begin || tw.sunrise;
      if (nightStart != null && nightEnd != null) {
        const nightPct = ((nightEnd - nightStart) / 24) * 100;
        const offsetPct = (nightStart / 24) * 100;
        const nightDiv = el("div", "astronomy-timeline-night");
        nightDiv.style.left = `${offsetPct}%`;
        nightDiv.style.width = `${nightPct}%`;
        timeline.appendChild(nightDiv);
      }
      panel.appendChild(timeline);

      /* Twilight detail rows */
      const twDetails = el("div", "astronomy-card-details");
      if (tw.sunset != null) twDetails.appendChild(detailRow("Sunset", formatHour(tw.sunset)));
      if (tw.civil_twilight_end != null) twDetails.appendChild(detailRow("Civil twilight end", formatHour(tw.civil_twilight_end)));
      if (tw.nautical_twilight_end != null) twDetails.appendChild(detailRow("Nautical twilight end", formatHour(tw.nautical_twilight_end)));
      if (tw.astro_twilight_end != null) twDetails.appendChild(detailRow("Astro twilight end", formatHour(tw.astro_twilight_end)));
      if (tw.astro_twilight_begin != null) twDetails.appendChild(detailRow("Astro twilight begin", formatHour(tw.astro_twilight_begin)));
      if (tw.nautical_twilight_begin != null) twDetails.appendChild(detailRow("Nautical twilight begin", formatHour(tw.nautical_twilight_begin)));
      if (tw.civil_twilight_begin != null) twDetails.appendChild(detailRow("Civil twilight begin", formatHour(tw.civil_twilight_begin)));
      if (tw.sunrise != null) twDetails.appendChild(detailRow("Sunrise", formatHour(tw.sunrise)));
      panel.appendChild(twDetails);
    }

    /* Moon phase */
    const moonRow = el("div", "astronomy-moon-row");
    const phase = ni.moon?.phase;
    const illumination = ni.moon?.illumination;
    moonRow.appendChild(el("span", "astronomy-moon-icon", moonEmoji(phase)));
    const moonInfo = el("div", "astronomy-moon-info");
    let moonText = illumination != null ? `Illumination: ${illumination}%` : "Moon info unavailable";
    if (phase != null) moonText += `\nPhase: ${(phase * 100).toFixed(0)}%`;
    moonInfo.textContent = moonText;
    moonInfo.style.whiteSpace = "pre-line";
    moonRow.appendChild(moonInfo);
    panel.appendChild(moonRow);

    return panel;
  }

  /* ── Target table ── */
  function targetTable() {
    if (!state.targets.length) return null;

    const section = el("div", "");
    section.appendChild(el("div", "astronomy-section-title", "⭐ Visible Targets"));

    const table = el("table", "astronomy-target-table");
    const thead = el("thead", "");
    const headRow = el("tr", "");
    for (const h of ["Name", "Type", "Alt", "Az", "Rise", "Set"]) {
      headRow.appendChild(el("th", "", h));
    }
    thead.appendChild(headRow);
    table.appendChild(thead);

    const tbody = el("tbody", "");
    for (const t of state.targets) {
      const tr = el("tr", "");
      tr.appendChild(el("td", "", t.name || "—"));
      tr.appendChild(el("td", "", t.type || "—"));

      /* Altitude with mini bar */
      const altTd = el("td", "");
      altTd.appendChild(document.createTextNode(t.alt != null ? `${t.alt.toFixed(1)}°` : "—"));
      if (t.alt != null) {
        const bar = el("span", "astronomy-target-alt");
        const fill = el("span", "astronomy-target-alt-fill");
        fill.style.width = `${Math.max(0, Math.min(100, (t.alt / 90) * 100))}%`;
        bar.appendChild(fill);
        altTd.appendChild(bar);
      }
      tr.appendChild(altTd);

      tr.appendChild(el("td", "", t.az != null ? `${t.az.toFixed(1)}°` : "—"));
      tr.appendChild(el("td", "", t.rise != null ? formatHour(t.rise) : "—"));
      tr.appendChild(el("td", "", t.set != null ? formatHour(t.set) : "—"));
      tbody.appendChild(tr);
    }
    table.appendChild(tbody);
    section.appendChild(table);
    return section;
  }

  function formatHour(h) {
    if (h == null) return "—";
    const hours = Math.floor(h);
    const mins = Math.round((h - hours) * 60);
    return `${hours.toString().padStart(2, "0")}:${mins.toString().padStart(2, "0")}`;
  }

  /* ── Main render ── */
  function render() {
    const root = document.getElementById("astronomy-root");
    if (!root) return;
    root.innerHTML = "";

    if (state.error) {
      root.appendChild(el("div", "astronomy-error-banner", `⚠ ${state.error}`));
    }

    /* Equipment section */
    root.appendChild(el("div", "astronomy-section-title", "🔭 Equipment"));

    if (state.loading) {
      const grid = el("div", "astronomy-equipment-grid");
      for (let i = 0; i < 3; i++) grid.appendChild(el("div", "astronomy-card", el("div", "astronomy-skeleton")));
      root.appendChild(grid);
    } else {
      const devices = state.status?.devices || [];
      if (devices.length === 0) {
        root.appendChild(el("div", "astronomy-error-banner",
          "ℹ No devices detected. Start the INDI bridge sidecar for telescope control."));
      } else {
        const grid = el("div", "astronomy-equipment-grid");
        for (const d of devices) grid.appendChild(equipmentCard(d));
        root.appendChild(grid);
      }
    }

    /* Night planning section */
    root.appendChild(el("div", "astronomy-section-title", "🌙 Night Planning"));
    root.appendChild(nightPanel());

    /* Target table */
    const targets = targetTable();
    if (targets) root.appendChild(targets);
  }

  /* ── Sidebar tab registration ── */
  function registerSidebarTab() {
    /* Use the Plugin SDK if available */
    const sdk = window.__HERMES_PLUGIN_SDK__ || window.__ARES_PLUGIN_SDK__;
    if (sdk?.registerTab) {
      sdk.registerTab({
        id: "astronomy",
        label: "Astronomy",
        icon: "🔭",
        slot: "sidebar",
        onMount(container) {
          container.id = "astronomy-root";
          container.classList.add("astronomy-root");
          state.loading = true;
          render();
          Promise.all([loadStatus(), loadNightInfo(), loadTargets()]).finally(() => {
            state.loading = false;
            render();
          });
        },
        onUnmount() {
          const el = document.getElementById("astronomy-root");
          if (el) el.innerHTML = "";
        },
      });
      return;
    }

    /* Fallback: inject as a sidebar panel directly */
    const main = document.querySelector("main");
    if (!main) return;

    const panel = document.createElement("section");
    panel.id = "astronomy-root";
    panel.className = "main-view astronomy-root";
    panel.hidden = true;
    main.appendChild(panel);

    /* Add sidebar button */
    const sidebar = document.querySelector('[data-testid="sidebar"]') ||
                    document.querySelector(".sidebar") ||
                    document.querySelector("nav");
    if (sidebar) {
      const btn = document.createElement("button");
      btn.className = "astronomy-sidebar-btn";
      btn.title = "Astronomy";
      btn.textContent = "🔭";
      btn.style.cssText = "background:none;border:none;color:inherit;font-size:18px;cursor:pointer;padding:8px;";
      btn.addEventListener("click", () => {
        document.querySelectorAll("main > .main-view").forEach((v) => {
          v.hidden = v !== panel;
        });
        state.loading = true;
        render();
        Promise.all([loadStatus(), loadNightInfo(), loadTargets()]).finally(() => {
          state.loading = false;
          render();
        });
      });
      sidebar.appendChild(btn);
    }
  }

  /* ── Boot ── */
  registerSidebarTab();
})();