import { stripTimeFromTitle } from '../src/format.js';
const cases = [
  ['CCCS Chapel Service @ 9:40 - 10:10', 'CCCS Chapel Service'],
  ['Early Dismissal @ 2:00p for Team Meetings', 'Early Dismissal for Team Meetings'],
  ['First Day of School! Half day Dismissal is at 12:00p', 'First Day of School! Half day Dismissal'],
  ['Spring Concert Grade 4 - 8 @ Cathedral', 'Spring Concert Grade 4 - 8 @ Cathedral'],
  ['Camp Thunderbird Grade 2 to 6', 'Camp Thunderbird Grade 2 to 6'],
  ['Grade 7 & 8 Assembly', 'Grade 7 & 8 Assembly'],
  ['P 5&6 Flex Time K to 8', 'P 5&6 Flex Time K to 8'],
  ['Choristers: Choral Evensong', 'Choristers: Choral Evensong'],
  ['Picture Day - First Takes', 'Picture Day - First Takes'],
  ['Assembly (9:00am - 10:00am)', 'Assembly'],
  ['9:40 - 10:10', '9:40 - 10:10'],
  ['Christmas Performance @ Cathedral - Matinee', 'Christmas Performance @ Cathedral - Matinee'],
  ['FSA Week Grade 4 & Grade 7', 'FSA Week Grade 4 & Grade 7'],
];
let fail = 0;
for (const [input, want] of cases) {
  const got = stripTimeFromTitle(input);
  const ok = got === want;
  if (!ok) fail++;
  console.log(ok ? 'ok  ' : 'FAIL', JSON.stringify(input), '->', JSON.stringify(got), ok ? '' : `(wanted ${JSON.stringify(want)})`);
}
console.log(fail ? `\n${fail} failing` : '\nall passing');
