/**
 * Presentation rules applied to calendar entries before they reach the display.
 * Kept apart from calendar.js, which is only concerned with what the iCal feed
 * actually says.
 */

// A clock time must carry either a colon or a meridiem to count. Without that
// rule, "Spring Concert Grade 4 - 8" and "Camp Thunderbird Grade 2 to 6" would
// look exactly like time ranges and lose half their titles.
const CLOCK = String.raw`(?:\d{1,2}:\d{2}(?:\s*[ap]\.?m?\.?)?|\d{1,2}\s*[ap]\.?m\.?)`;

const TIME_RANGE = new RegExp(
  String.raw`\s*(?:@|at|from)?\s*${CLOCK}\s*(?:-|–|—|to|until)\s*${CLOCK}`,
  'gi'
);

// A lone time is only stripped when it is introduced by "@" or "at", so a bare
// number in a title is never mistaken for a clock.
const SINGLE_TIME = new RegExp(String.raw`\s*(?:@|at)\s*${CLOCK}`, 'gi');

// Whatever the time was hanging off — "Dismissal is at 12:00p" leaves "is at".
const DANGLING = /[\s,;:@-]*\b(?:is|are|starts?|starting|begins?|beginning|runs?|from|at|on)\b[\s,;:@-]*$/i;
const TRAILING_PUNCTUATION = /[\s,;:@\-–—]+$/;
const EMPTY_BRACKETS = /\(\s*\)|\[\s*\]/g;

/**
 * Staff often write the time into the event name — "CCCS Chapel Service @ 9:40
 * - 10:10". The board already shows the time on its own line, so repeating it
 * in the title is noise.
 */
export function stripTimeFromTitle(title) {
  if (!title) return title;

  const stripped = title
    .replace(TIME_RANGE, ' ')
    .replace(SINGLE_TIME, ' ')
    .replace(EMPTY_BRACKETS, ' ')
    .replace(/\s+/g, ' ')
    .replace(DANGLING, '')
    .replace(TRAILING_PUNCTUATION, '')
    .trim();

  // Never hand back nothing: if a title was only a time, keep what was written.
  return stripped || title;
}

/**
 * Some events always happen in the same place but are not tagged with it in
 * Google Calendar. theme.json can name those, so the board fills the location in
 * without anyone having to edit hundreds of calendar entries.
 */
export function applyLocationRules(event, rules) {
  if (!Array.isArray(rules) || !rules.length) return event;

  for (const rule of rules) {
    if (!rule?.match || !rule?.location) continue;
    if (!new RegExp(rule.match, 'i').test(event.title)) continue;
    // An explicit location in the calendar wins unless the rule says otherwise.
    if (event.location && rule.override !== true) return event;
    return { ...event, location: rule.location };
  }

  return event;
}

export function presentEvent(event, rules) {
  return applyLocationRules({ ...event, title: stripTimeFromTitle(event.title) }, rules);
}
