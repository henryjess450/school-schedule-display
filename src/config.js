import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const themePath = path.join(rootDir, 'config', 'theme.json');

/**
 * Reads .env into the environment. Docker does this for us via env_file, but the
 * display also runs as a plain Node process on Windows, where nothing would
 * otherwise load it — and a missing ICAL_URL means a board that only ever says
 * the calendar is unreachable.
 *
 * Anything already set in the real environment wins, so a value passed on the
 * command line or by Docker still overrides the file.
 */
function loadEnvFile() {
  const envPath = path.join(rootDir, '.env');
  if (!fs.existsSync(envPath)) return;

  for (const rawLine of fs.readFileSync(envPath, 'utf8').split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;

    const separator = line.indexOf('=');
    if (separator < 1) continue;

    const key = line.slice(0, separator).trim();
    let value = line.slice(separator + 1).trim();

    // Allow quoted values so a setting can keep leading or trailing spaces.
    if (value.length > 1 && ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'")))) {
      value = value.slice(1, -1);
    }

    if (!(key in process.env)) process.env[key] = value;
  }
}

loadEnvFile();

// The whole app treats local time as school time, so TZ has to be in effect
// before any Date is created. Node caches the zone, and re-assigning TZ is what
// clears that cache — needed here because the value only just arrived from .env.
if (process.env.TZ) {
  const zone = process.env.TZ;
  delete process.env.TZ;
  process.env.TZ = zone;
}

/**
 * Theme lives in config/theme.json so the whole look can be re-skinned for a
 * school without touching code. Environment variables win where they overlap,
 * which is what lets docker-compose override things per site.
 */
export function loadTheme() {
  const theme = JSON.parse(fs.readFileSync(themePath, 'utf8'));
  if (process.env.SCHOOL_NAME) theme.schoolName = process.env.SCHOOL_NAME;
  if (process.env.SCHOOL_TAGLINE) theme.tagline = process.env.SCHOOL_TAGLINE;
  return theme;
}

export const config = {
  port: Number(process.env.PORT || 8080),
  icalUrl: process.env.ICAL_URL || '',
  timezone: process.env.TZ_NAME || 'America/Vancouver',
  // How often the server re-fetches the calendar from Google. The browser polls
  // this server on the same cadence, so a change made in Google Calendar reaches
  // the panel within a few minutes. Anything in the 60-480s range is sensible.
  refreshSeconds: Number(process.env.REFRESH_SECONDS || 120),
  rootDir,
};
