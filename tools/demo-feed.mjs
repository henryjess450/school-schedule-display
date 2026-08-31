/**
 * Serves a fake school day as an iCal feed, so the display can be set up and
 * checked on the panel before the real calendar link is available.
 *
 *   node tools/demo-feed.mjs
 *   ICAL_URL=http://localhost:9999/demo.ics npm start
 *
 * Events are generated around the current time, so one of them is always
 * "happening now" and shows the gold highlight.
 */
import http from 'node:http';

const PORT = Number(process.env.DEMO_PORT || 9999);

const DAY = [
  { title: 'Whole School Chapel', location: 'Cathedral', offset: -160, minutes: 60 },
  { title: 'Grade 7 & 8 Assembly', location: 'Great Hall', offset: -85, minutes: 45 },
  { title: 'Junior Kindergarten Music', location: 'Music Room', offset: -10, minutes: 40 },
  { title: 'Cross Country Practice', location: 'Front Field', offset: 60, minutes: 60 },
  { title: 'Parent Council Meeting', location: 'Library', offset: 140, minutes: 60 },
];

function stamp(date) {
  const pad = (n) => String(n).padStart(2, '0');
  return `${date.getFullYear()}${pad(date.getMonth() + 1)}${pad(date.getDate())}`
    + `T${pad(date.getHours())}${pad(date.getMinutes())}00`;
}

function buildFeed() {
  const now = new Date();
  const zone = process.env.TZ || 'America/Vancouver';

  const events = DAY.map((entry, index) => {
    const start = new Date(now.getTime() + entry.offset * 60000);
    const end = new Date(start.getTime() + entry.minutes * 60000);
    return [
      'BEGIN:VEVENT',
      `UID:demo-${index}@schedule-display`,
      `SUMMARY:${entry.title}`,
      `LOCATION:${entry.location}`,
      `DTSTART;TZID=${zone}:${stamp(start)}`,
      `DTEND;TZID=${zone}:${stamp(end)}`,
      'END:VEVENT',
    ].join('\r\n');
  });

  return [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//school-schedule-display//demo//EN',
    ...events,
    'END:VCALENDAR',
  ].join('\r\n');
}

http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/calendar; charset=utf-8' });
  res.end(buildFeed());
}).listen(PORT, () => {
  console.log(`Demo calendar feed on http://localhost:${PORT}/demo.ics`);
});
