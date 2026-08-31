import ical from 'node-ical';

const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * The container runs with TZ set to the school's timezone, so plain local-time
 * arithmetic is already school time. Everything below relies on that.
 */
function dayKey(date) {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

function utcDayKey(date) {
  const y = date.getUTCFullYear();
  const m = String(date.getUTCMonth() + 1).padStart(2, '0');
  const d = String(date.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

// DATE-valued (all-day) entries come back from node-ical as either UTC midnight
// or local midnight depending on how the feed was written. Pick whichever
// reading actually lands on midnight so an event never slides a day.
function allDayKey(date) {
  if (date.getHours() === 0 && date.getMinutes() === 0) return dayKey(date);
  return utcDayKey(date);
}

function isAllDay(component) {
  return component.datetype === 'date' || component.start?.dateOnly === true;
}

function startOfDay(date) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

function cleanText(value) {
  if (!value) return '';
  return String(value).replace(/\s+/g, ' ').trim();
}

const MAX_LOCATION_CHARS = 40;

/**
 * Google hands back whatever Maps matched, so a location is routinely a full
 * postal address. On a wall display only the venue name is useful, and a long
 * one would push the rest of the day off the panel.
 */
function shortLocation(value) {
  const text = cleanText(value);
  if (!text) return '';

  const venue = text.split(',')[0].trim();
  // A leading street number means the first segment is an address, not a name.
  const looksLikeStreet = /^\d+\s/.test(venue);
  const chosen = (venue && !looksLikeStreet) ? venue : text;

  return chosen.length > MAX_LOCATION_CHARS
    ? `${chosen.slice(0, MAX_LOCATION_CHARS - 1).trimEnd()}…`
    : chosen;
}

function toEntry(component, start, end) {
  const allDay = isAllDay(component);
  return {
    uid: `${component.uid || 'event'}@${start.getTime()}`,
    title: cleanText(component.summary) || 'Untitled',
    location: shortLocation(component.location),
    description: cleanText(component.description),
    allDay,
    start: start.toISOString(),
    end: end.toISOString(),
  };
}

/**
 * Expands a parsed iCal feed into the entries that touch a single day,
 * including recurring events and their per-instance overrides.
 */
export function eventsForDay(parsed, target = new Date()) {
  const windowStart = startOfDay(target);
  const windowEnd = new Date(windowStart.getTime() + DAY_MS);
  const key = dayKey(windowStart);
  const entries = [];

  for (const component of Object.values(parsed)) {
    if (!component || component.type !== 'VEVENT' || !component.start) continue;

    const duration = component.end
      ? component.end.getTime() - component.start.getTime()
      : (isAllDay(component) ? DAY_MS : 60 * 60 * 1000);

    if (!component.rrule) {
      if (isAllDay(component)) {
        // An all-day block can span several days; walk it day by day.
        const days = Math.max(1, Math.round(duration / DAY_MS));
        for (let i = 0; i < days; i += 1) {
          const at = new Date(component.start.getTime() + i * DAY_MS);
          if (allDayKey(at) === key) {
            entries.push(toEntry(component, windowStart, windowEnd));
            break;
          }
        }
      } else if (component.start < windowEnd && new Date(component.start.getTime() + duration) > windowStart) {
        entries.push(toEntry(component, component.start, new Date(component.start.getTime() + duration)));
      }
      continue;
    }

    // Recurring. Look back by the event's own length so a block that started
    // yesterday and runs into today is still caught.
    const searchStart = new Date(windowStart.getTime() - duration - DAY_MS);
    let occurrences = [];
    try {
      occurrences = component.rrule.between(searchStart, windowEnd, true);
    } catch {
      occurrences = [];
    }

    const excluded = new Set(
      Object.values(component.exdate || {}).map((d) => (isAllDay(component) ? allDayKey(d) : d.getTime()))
    );

    for (const occurrence of occurrences) {
      const override = (component.recurrences || {})[dayKey(occurrence)]
        || (component.recurrences || {})[utcDayKey(occurrence)];
      const source = override || component;

      if (excluded.has(isAllDay(component) ? allDayKey(occurrence) : occurrence.getTime())) continue;

      const start = override ? override.start : occurrence;
      const span = override && override.end
        ? override.end.getTime() - override.start.getTime()
        : duration;
      const end = new Date(start.getTime() + span);

      if (isAllDay(source)) {
        if (allDayKey(start) === key) entries.push(toEntry(source, windowStart, windowEnd));
      } else if (start < windowEnd && end > windowStart) {
        entries.push(toEntry(source, start, end));
      }
    }
  }

  // All-day banners first, then chronological.
  entries.sort((a, b) => {
    if (a.allDay !== b.allDay) return a.allDay ? -1 : 1;
    return new Date(a.start) - new Date(b.start);
  });

  // A feed can list the same occurrence twice (override plus base). Keep one.
  const seen = new Set();
  return entries.filter((e) => {
    const signature = `${e.title}|${e.start}|${e.end}`;
    if (seen.has(signature)) return false;
    seen.add(signature);
    return true;
  });
}

export async function fetchCalendar(url) {
  if (!url) throw new Error('ICAL_URL is not set');
  return ical.async.fromURL(url);
}

export { dayKey };
