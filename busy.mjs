import { fetchCalendar, eventsForDay } from '/Users/hjess/LightLabProduction/Claude/school-schedule-display/src/calendar.js';
const parsed = await fetchCalendar('https://calendar.google.com/calendar/ical/reception%40cathedralschool.ca/public/basic.ics');
let best = [];
for (let i = 0; i < 300; i++) {
  const day = new Date(2026, 7, 30 + i);
  const n = eventsForDay(parsed, day).length;
  best.push([n, day.toDateString(), day]);
}
best.sort((a,b) => b[0]-a[0]);
for (const [n, label, d] of best.slice(0,5)) {
  console.log(n, label, `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`);
}
