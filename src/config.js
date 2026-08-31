import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const themePath = path.join(rootDir, 'config', 'theme.json');

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
