# Christ Church Cathedral School — Daily Schedule Display

A wall display that shows today's events from the school's Google Calendar, in
the school's own branding. Installs from a USB stick, opens full screen on a
Windows PC with the touchscreen switched off, and looks after itself from then
on.

---

## What it does

- Reads the school's public Google Calendar iCal feed — no API keys, no OAuth.
- Shows **today only**, in Pacific time, with the event that is happening now
  picked out in the school's gold.
- Re-checks the calendar every **2 minutes**, so a change made in Google Calendar
  reaches the panel within a few minutes.
- Corrects its own clock against the server on every check, so the right event is
  highlighted even if the PC's clock has drifted.
- Rolls over to the next day on its own at midnight.
- Keeps showing the last known schedule if the network drops, with a small
  "Calendar unreachable" note rather than a blank screen.
- Shrinks the type automatically on a busy day so the whole day always fits.
- Drops the time out of an event's name when staff have written it there —
  "CCCS Chapel Service @ 9:40 - 10:10" shows as "CCCS Chapel Service", since the
  time is already on its own line.
- Fills in locations the calendar leaves blank, via `locationRules` in the theme
  (chapel services are shown as being in the Nave).
- Goes into **rest mode** outside school hours — from 4:00pm until 7:30am the
  next morning the panel is black, showing only the current time and a note that
  the display is asleep.

---

## Setting it up on the display PC

The display installs from a USB stick. The PC needs nothing beforehand — no
Node, no Docker, no internet connection during setup.

1. Plug the stick in.
2. Double-click **INSTALL.bat**.
3. Click **Yes** when Windows asks for permission.
4. Wait a minute or two while it copies.
5. The schedule appears full screen. Unplug the stick.

The installer copies the app to `C:\CathedralScheduleDisplay`, turns the
touchscreen off, stops the PC sleeping and blanking, silences notification
pop-ups, and registers three scheduled tasks: launch at logon, a watchdog every
5 minutes, and a 3:30am reboot so Windows Update never interrupts the school day.

**UNINSTALL.bat** undoes all of it, touchscreen included.

### The one manual step

Set the account to sign in automatically, or a reboot leaves the panel on the
lock screen. Run `netplwiz`, untick *Users must enter a user name and password*,
and enter the account's password. A script cannot do this safely.

### Building the stick

```bash
./tools/build-usb.sh
```

Assembles `~/Downloads/CathedralScheduleDisplay-USB` — about 105MB, most of it
the bundled Node runtime. It downloads the official Windows Node build and
checks it against the published SHA-256 before packaging. Copy the *contents* of
that folder onto the stick.

### Running it in Docker instead

The Dockerfile and compose file are still here if you would rather run it that
way on a Linux box or a server:

```bash
cp .env.example .env
docker compose up -d --build
```

## Day-to-day

| I want to… | Do this |
|---|---|
| Start it now without rebooting | `schtasks /run /tn CathedralScheduleDisplay` |
| Get out of kiosk mode | `Alt+F4`, or `Ctrl+Alt+Del` → Task Manager |
| Change the wording or colours | Edit `C:\CathedralScheduleDisplay\config\theme.json` (takes effect on the next refresh) |
| Check an upcoming day | Open `http://localhost:8080/?date=2026-09-18` |
| See the board outside school hours | Same thing — `?date=` never goes into rest mode |
| Change the rest hours | Edit `rest` in `config/theme.json` |
| See what the app thinks is wrong | `http://localhost:8080/healthz` |
| Read the logs | `C:\CathedralScheduleDisplay\logs\` |
| Update the display | Run `INSTALL.bat` from a fresh stick — settings are kept |
| Undo everything | Double-click `UNINSTALL.bat` |

Branding changes need no restart at all: `config/theme.json` is read on every
request, so an edit shows up on the panel within a couple of minutes.

---

## Branding

Everything visible is in [`config/theme.json`](config/theme.json):

```jsonc
{
  "heading": "Today at a glance:",
  "logo": {
    "image":    "/assets/logo.avif",   // served first
    "fallback": "/assets/logo.png",    // used if AVIF is unsupported
    "alt":      "Christ Church Cathedral School — Junior Kindergarten to Grade 8"
  },
  "footer": {
    "managedBy": "Proudly Managed by Cathedral School Alum",
    "contact": "Questions or Concerns? cccs@henryjess.ca"
  },
  "colors": { "navy": "#17265b", "gold": "#f0b323", … },
  "highlightCurrent": true,   // gold highlight on the event happening now

  // Fills in a location for events the calendar does not tag with one.
  // "match" is a case-insensitive pattern tested against the event name.
  "locationRules": [
    { "match": "chapel", "location": "Nave" }
  ],

  // The panel goes black outside these hours. The window wraps past midnight:
  // rest from 16:00 until 07:30 the following morning.
  "rest": {
    "enabled": true,
    "start": "16:00",
    "end": "07:30",
    "message": "This display is in rest mode, do not touch.",
    "timeLabel": "Current Time:"
  }
}
```

The logo is the school's white-and-gold lockup on transparency, so it sits
directly on the navy. To replace it, drop the new file into `public/assets/`,
point `logo.image` at it. On the display PC that folder is
`C:\CathedralScheduleDisplay\public\assets\`. Keep a PNG in `logo.fallback`:
it is what renders if the display ever runs a browser without AVIF support.

---

## Full lockdown (optional)

The kiosk scripts stop the display being *disturbed*. If the panel is somewhere
students can reach the keyboard, Windows can lock it down properly with
**Assigned Access**:

> Settings → Accounts → Other users → Set up a kiosk

Point it at Microsoft Edge in kiosk mode with `http://localhost:8080` as the
start URL. That account can then run nothing else at all.

This replaces the logon task rather than adding to it, so the schedule server
needs starting another way — register `windows\Start-Display.ps1` as a task that
runs at system startup under SYSTEM, and let Assigned Access handle only the
browser.

---

## Developing without the school's calendar

```bash
npm install
node tools/demo-feed.mjs &                      # fake school day on :9999
ICAL_URL=http://localhost:9999/demo.ics npm start
```

The demo feed generates events around the current time, so one is always
"happening now".

---

## How it fits together

```
Google Calendar (public .ics)
        │  fetched every 2 min, cached in memory
        ▼
  Node + Express  ──►  /api/schedule   today's events, expanded from recurrence
 (bundled runtime) ──►  /api/theme      branding
                  ──►  /healthz        used by the kiosk launcher and watchdog
        │
        ▼
  Edge in kiosk mode, full screen, touch disabled
```

Recurring events, per-instance overrides, cancellations and multi-day all-day
events are all expanded server-side, so the browser only ever receives a plain
list for one day.

| File | What it is |
|---|---|
| `src/server.js` | HTTP server, calendar cache, API |
| `src/calendar.js` | iCal parsing and recurrence expansion |
| `public/` | The display itself |
| `config/theme.json` | All branding |
| `windows/` | Kiosk setup scripts run by the installer |
| `usb/` | The double-click launchers that sit on the stick |
| `tools/build-usb.sh` | Builds the USB stick |
| `src/format.js` | Tidies event names, applies location rules |
| `tools/demo-feed.mjs` | Fake calendar for testing |
| `tools/format-test.mjs` | Checks the name tidying (`node tools/format-test.mjs`) |
