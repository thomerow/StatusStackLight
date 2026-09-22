// StatusStackLight relay - small helpers for the admin interface.
"use strict";

// --- Stack light preview ------------------------------------------------------
//
// Same formulas as the firmware (lamps.cpp), so the preview blinks and pulses like the real
// thing: blink is on for the duty share of the period, pulse is a raised cosine that starts dark.
function lampLevel(seg, seconds) {
  const d = seg.dataset;
  if (d.on !== "1") return 0;
  const b = +d.brightness, f = +d.frequency, duty = +d.duty;
  const phase = (seconds * f) % 1;
  switch (d.effect) {
    case "blink": return phase < duty / 100 ? b : 0;
    case "pulse": return (0.5 - 0.5 * Math.cos(2 * Math.PI * phase)) * b;
    default:      return b;
  }
}

function animateStacks() {
  const seconds = performance.now() / 1000;
  for (const seg of document.querySelectorAll(".stack .seg")) {
    const level = lampLevel(seg, seconds) / 100;
    // Square root: a lamp at 30 % still looks clearly lit, as the real LEDs do.
    seg.style.opacity = (0.12 + 0.88 * Math.sqrt(level)).toFixed(3);
    seg.style.boxShadow = level > 0 ? `0 0 ${Math.round(4 + 14 * level)}px ${Math.round(3 * level)}px var(--c)` : "none";
  }
  requestAnimationFrame(animateStacks);
}
requestAnimationFrame(animateStacks);

function setStack(stack, lamps) {
  for (const seg of stack.querySelectorAll(".seg")) {
    const l = lamps[seg.dataset.lamp];
    if (!l) continue;
    seg.dataset.on = l.on ? "1" : "0";
    seg.dataset.effect = l.effect;
    seg.dataset.brightness = l.brightness;
    seg.dataset.frequency = l.frequency;
    seg.dataset.duty = l.duty;
  }
}

// --- Confirmations and copy buttons -----------------------------------------------
document.addEventListener("submit", e => {
  const msg = e.submitter?.dataset.confirm ?? e.target.dataset.confirm;
  if (msg && !confirm(msg)) e.preventDefault();
});

document.addEventListener("click", async e => {
  const btn = e.target.closest("[data-copy]");
  if (!btn) return;
  const text = document.getElementById(btn.dataset.copy)?.textContent ?? "";
  try {
    await navigator.clipboard.writeText(text.trim());
    const old = btn.textContent;
    btn.textContent = "Copied";
    setTimeout(() => btn.textContent = old, 1500);
  } catch { /* clipboard blocked (plain http): the key can still be selected by hand */ }
});

// --- Display page: live preview of each state while editing -----------------------
for (const card of document.querySelectorAll("[data-state-card]")) {
  const stack = card.querySelector(".stack");
  const update = () => {
    const lamps = {};
    for (const row of card.querySelectorAll("[data-lamp-row]")) {
      const v = n => row.querySelector(`[data-field=${n}]`);
      lamps[row.dataset.lampRow] = {
        on: v("use").checked,
        effect: v("effect").value.toLowerCase(),
        brightness: v("brightness").value,
        frequency: v("frequency").value,
        duty: v("duty").value,
      };
    }
    setStack(stack, lamps);
  };
  card.addEventListener("input", update);
  card.addEventListener("change", update);
  update();
}

// --- Dashboard: refresh every two seconds ----------------------------------------------
const dashboard = document.getElementById("dashboard");
if (dashboard) {
  const esc = s => String(s ?? "").replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
  const ago = s => s < 60 ? `${s} s` : s < 3600 ? `${Math.floor(s / 60)} min` : `${Math.floor(s / 3600)} h`;

  async function refresh() {
    try {
      const r = await fetch(dashboard.dataset.statusUrl, { cache: "no-store", credentials: "same-origin" });
      if (r.status === 401) { location.reload(); return; }
      const s = await r.json();

      setStack(dashboard.querySelector(".stack"), s.lamps);
      const state = dashboard.querySelector("[data-state]");
      state.textContent = s.state ?? "no session";
      state.classList.toggle("none", !s.state);
      dashboard.querySelector("[data-error]").hidden = !s.error;
      dashboard.querySelector("[data-flash]").hidden = !s.flash;
      dashboard.querySelector("[data-version]").textContent = s.version;

      dashboard.querySelector("[data-sessions]").innerHTML = s.sessions.length
        ? s.sessions.map(x => `<tr><td class="mono">${esc(x.id)}</td><td>${esc(x.host ?? "–")}</td>
            <td>${esc(x.state)}${x.error ? ' <span class="pill bad">error</span>' : ""}</td>
            <td class="num">${ago(x.idleSeconds)} ago</td></tr>`).join("")
        : `<tr><td colspan="4" class="muted">No open session.</td></tr>`;

      const now = Date.now();
      dashboard.querySelector("[data-lights]").innerHTML = s.stackLights.length
        ? s.stackLights.map(x => {
            const age = Math.max(0, Math.round((now - Date.parse(x.lastSeen)) / 1000));
            const live = x.polling || age < 40;
            return `<tr><td>${esc(x.name)}</td>
              <td>${live ? '<span class="pill ok">connected</span>' : '<span class="pill bad">gone</span>'}</td>
              <td class="mono">${esc(x.localAddress ?? "–")}</td><td class="mono">${esc(x.remoteAddress ?? "–")}</td>
              <td>${esc(x.firmware ?? "–")}</td><td class="num">${x.polling ? "waiting for a change" : ago(age) + " ago"}</td></tr>`;
          }).join("")
        : `<tr><td colspan="6" class="muted">No stack light has polled since the relay started.</td></tr>`;
    } catch { /* relay restarting - try again on the next round */ }
  }
  refresh();
  setInterval(refresh, 2000);
}
