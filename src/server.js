import path from 'node:path';
import express from 'express';
import { config, loadTheme } from './config.js';
import { fetchCalendar, eventsForDay, dayKey } from './calendar.js';
import { presentEvent } from './format.js';

const app = express();

// Cached calendar. The display must keep showing yesterday's good data if the
// network drops, so a failed refresh never clears what we already have.
const cache = {
  parsed: null,
  fetchedAt: 0,
  lastError: null,
};

async function refreshCalendar(force = false) {
  const age = Date.now() - cache.fetchedAt;
  if (!force && cache.parsed && age < config.refreshSeconds * 1000) return cache.parsed;

  try {
    cache.parsed = await fetchCalendar(config.icalUrl);
    cache.fetchedAt = Date.now();
    cache.lastError = null;
  } catch (error) {
    cache.lastError = error.message;
    console.error(`[calendar] refresh failed: ${error.message}`);
  }
  return cache.parsed;
}

// Optional ?date=YYYY-MM-DD renders that day instead of today. Used during
// setup to check an upcoming school day; the display itself never sends it.
function requestedDay(value) {
  if (typeof value !== 'string') return null;
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) return null;
  const [, year, month, day] = match.map(Number);
  const date = new Date(year, month - 1, day, 12);
  return Number.isNaN(date.getTime()) ? null : date;
}

app.get('/api/schedule', async (req, res) => {
  const parsed = await refreshCalendar();
  const preview = requestedDay(req.query.date);
  const now = preview || new Date();

  if (!parsed) {
    return res.status(503).json({
      error: cache.lastError || 'Calendar unavailable',
      events: [],
      now: now.toISOString(),
    });
  }

  // Theme is read per request so branding and location rules can be edited
  // without restarting; it is a small local file.
  let locationRules = [];
  try {
    locationRules = loadTheme().locationRules || [];
  } catch (error) {
    console.error(`[theme] ${error.message}`);
  }

  const events = eventsForDay(parsed, now).map((event) => presentEvent(event, locationRules));
  res.json({
    date: dayKey(now),
    now: now.toISOString(),
    preview: Boolean(preview),
    timezone: config.timezone,
    stale: Boolean(cache.lastError),
    lastUpdated: new Date(cache.fetchedAt).toISOString(),
    events,
  });
});

app.get('/api/theme', (req, res) => {
  try {
    res.json(loadTheme());
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Used by the kiosk launcher to wait for the container before opening the browser.
app.get('/healthz', (req, res) => {
  res.json({
    ok: true,
    calendarLoaded: Boolean(cache.parsed),
    lastError: cache.lastError,
  });
});

// The kiosk browser runs for weeks without a human to press refresh, so never
// let it hold a stale stylesheet or script after the display is updated.
app.use(express.static(path.join(config.rootDir, 'public'), {
  etag: false,
  lastModified: false,
  setHeaders: (res) => res.setHeader('Cache-Control', 'no-store'),
}));

app.listen(config.port, () => {
  console.log(`Schedule display listening on http://localhost:${config.port}`);
  if (!config.icalUrl) console.warn('WARNING: ICAL_URL is empty — the display will show an error card.');
  refreshCalendar(true);
});
