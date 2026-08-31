(() => {
  'use strict';

  const SCHEDULE_POLL_MS = 2 * 60 * 1000;  // check for calendar changes every 2 min
  const TICK_MS = 20 * 1000;               // re-evaluate what is "now" every 20 s
  const MIN_SCALE = 0.5;                   // how far the agenda may shrink to fit

  let theme = null;
  let state = { events: [], stale: false, error: null, lastUpdated: null, date: null };

  // Every time is rendered in the school's timezone rather than the browser's,
  // so a display whose Windows clock is set to the wrong zone still reads right.
  let displayZone;

  // A kiosk PC that has drifted (or never synced) would otherwise highlight the
  // wrong event. Each poll re-measures the gap between this browser's clock and
  // the server's, and every "now" below is corrected by it.
  let clockOffsetMs = 0;

  const now = () => new Date(Date.now() + clockOffsetMs);

  const el = (id) => document.getElementById(id);

  /* ---------- theme ---------- */

  function applyTheme(t) {
    theme = t || {};
    const root = document.documentElement.style;
    const c = theme.colors || {};
    const tokens = {
      '--navy': c.navy,
      '--navy-deep': c.navyDeep,
      '--gold': c.gold,
      '--text': c.text,
      '--text-soft': c.textSoft,
      '--rule': c.rule,
      '--font-body': theme.fonts?.body,
    };
    for (const [prop, value] of Object.entries(tokens)) {
      if (value) root.setProperty(prop, value);
    }

    if (theme.fonts?.googleFontsHref) {
      const link = document.createElement('link');
      link.rel = 'stylesheet';
      link.href = theme.fonts.googleFontsHref;
      document.head.appendChild(link);
    }

    el('heading').textContent = theme.heading || 'Today at a glance:';
    document.title = theme.schoolName ? `${theme.schoolName} — Today at a glance` : 'Today at a glance';

    applyLogo(theme.logo || {});

    el('updated-label').textContent = theme.labels?.lastUpdated || 'Last Updated:';
    el('managed-by').textContent = theme.footer?.managedBy || '';
    el('contact').textContent = theme.footer?.contact || '';
  }

  /**
   * The school's own lockup, served as AVIF with a PNG fallback so it renders
   * on any browser the display might end up running.
   */
  function applyLogo(logo) {
    const img = el('logo');
    const avif = el('logo-avif');

    const primary = logo.image || '';
    const fallback = logo.fallback || primary;

    if (primary && primary !== fallback) avif.srcset = primary;
    img.src = fallback || primary;
    img.alt = logo.alt || theme.schoolName || '';
  }

  /* ---------- formatting ---------- */

  function formatTime(date) {
    const twelve = (theme?.clockFormat || '12h') === '12h';
    return new Intl.DateTimeFormat('en-CA', {
      hour: 'numeric',
      minute: '2-digit',
      hour12: twelve,
      timeZone: displayZone,
    })
      .format(date)
      .replace(/\s?([ap])\.?m\.?/i, (_, meridiem) => meridiem.toLowerCase() + 'm');
  }

  function formatRange(event) {
    if (event.allDay) return 'All day';
    return `${formatTime(new Date(event.start))} - ${formatTime(new Date(event.end))}`;
  }

  function ordinal(n) {
    const teens = n % 100;
    if (teens >= 11 && teens <= 13) return `${n}TH`;
    return `${n}${['TH', 'ST', 'ND', 'RD'][n % 10] || 'TH'}`;
  }

  function formatUpdated(iso) {
    if (!iso) return '';
    const date = new Date(iso);
    // Matches the printed layout: "3:03PM, AUGUST 23RD, 2026".
    const time = new Intl.DateTimeFormat('en-CA', {
      hour: 'numeric', minute: '2-digit', hour12: true, timeZone: displayZone,
    }).format(date).replace(/[\s.]/g, '').toUpperCase();

    const parts = Object.fromEntries(
      new Intl.DateTimeFormat('en-CA', {
        month: 'long', day: 'numeric', year: 'numeric', timeZone: displayZone,
      }).formatToParts(date).map((p) => [p.type, p.value])
    );

    return `${time}, ${parts.month.toUpperCase()} ${ordinal(Number(parts.day))}, ${parts.year}`;
  }

  /* ---------- rendering ---------- */

  function renderAgenda(currentTime) {
    const list = el('agenda');
    list.innerHTML = '';
    list.style.fontSize = '';

    if (!state.events.length) {
      const empty = document.createElement('li');
      empty.className = 'agenda-empty';
      empty.textContent = state.error
        ? "Today's schedule is unavailable."
        : (theme?.labels?.emptyDay || 'Nothing scheduled today.');
      list.appendChild(empty);
      return;
    }

    for (const event of state.events) {
      const start = new Date(event.start);
      const end = new Date(event.end);

      const item = document.createElement('li');
      item.className = 'entry';
      if (event.allDay) {
        item.classList.add('is-all-day');
      } else if (start <= currentTime && end > currentTime) {
        if (theme?.highlightCurrent !== false) item.classList.add('is-now');
      } else if (end <= currentTime) {
        item.classList.add('is-past');
      }

      const time = document.createElement('div');
      time.className = 'entry-time';
      time.textContent = formatRange(event);

      const name = document.createElement('div');
      name.className = 'entry-name';
      name.textContent = event.title;

      if (event.location) {
        const detail = document.createElement('span');
        detail.className = 'detail';
        detail.textContent = ` — ${event.location}`;
        name.appendChild(detail);
      }

      item.append(time, name);
      list.appendChild(item);
    }

    fitAgenda(list);
  }

  /**
   * A packed timetable must never be silently cut off, so shrink the list until
   * the whole day fits on the panel.
   */
  function fitAgenda(list) {
    const base = parseFloat(getComputedStyle(list).fontSize);
    let scale = 1;
    while (list.scrollHeight > list.clientHeight && scale > MIN_SCALE) {
      scale -= 0.04;
      list.style.fontSize = `${base * scale}px`;
    }
  }

  function render() {
    renderAgenda(now());
    el('updated-value').textContent = formatUpdated(state.lastUpdated);
    el('offline-flag').hidden = !(state.stale || state.error);
  }

  /* ---------- data ---------- */

  // Opening the board as ?date=YYYY-MM-DD previews an upcoming school day.
  // Only used by a person checking the layout during setup.
  const previewDate = new URLSearchParams(window.location.search).get('date');

  async function loadSchedule() {
    try {
      const url = previewDate ? `/api/schedule?date=${encodeURIComponent(previewDate)}` : '/api/schedule';
      const response = await fetch(url, { cache: 'no-store' });
      const payload = await response.json();

      if (!response.ok) {
        // Keep whatever is already on screen; just flag it as stale.
        state.error = payload.error || `HTTP ${response.status}`;
        state.stale = true;
        return;
      }

      // A day rollover means the board should start the next day fresh.
      if (state.date && payload.date && state.date !== payload.date) {
        window.location.reload();
        return;
      }

      displayZone = payload.timezone || undefined;
      if (payload.now && !payload.preview) {
        clockOffsetMs = new Date(payload.now).getTime() - Date.now();
      }
      state = {
        events: payload.events || [],
        stale: Boolean(payload.stale),
        error: null,
        lastUpdated: payload.lastUpdated,
        date: payload.date,
      };
    } catch (error) {
      state.error = error.message;
      state.stale = true;
    }
  }

  async function boot() {
    try {
      applyTheme(await (await fetch('/api/theme', { cache: 'no-store' })).json());
    } catch {
      applyTheme({});
    }

    await loadSchedule();
    el('boot').hidden = true;
    el('app').hidden = false;

    // Webfonts change every metric the fit routine depends on, so measure again
    // once they have actually landed.
    render();
    if (document.fonts?.ready) document.fonts.ready.then(render);

    setInterval(render, TICK_MS);
    setInterval(loadSchedule, SCHEDULE_POLL_MS);
    window.addEventListener('resize', render);
  }

  // Kiosk hygiene in the page itself; the OS-level lockdown is the real guard.
  document.addEventListener('contextmenu', (e) => e.preventDefault());
  document.addEventListener('dragstart', (e) => e.preventDefault());
  document.addEventListener('keydown', (e) => {
    if (e.key === 'F5' || (e.ctrlKey && ['r', 'p', 'f', 's'].includes(e.key.toLowerCase()))) {
      e.preventDefault();
    }
  });

  boot();
})();
