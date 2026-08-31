# Christ Church Cathedral School — Daily Schedule Display

A wall display that shows today's events from the school's Google Calendar, in
the school's own branding. Runs in Docker, opens full screen on a Windows PC
with the touchscreen switched off, and looks after itself from then on.

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

You need **Docker Desktop** and **Git** installed, and the PC signed in to the
account the display will run under.

### 1. Get the code

```powershell
git clone https://github.com/henryjess450/school-schedule-display.git
cd school-schedule-display
```

### 2. Point it at the calendar

```powershell
copy .env.example .env
```

`.env.example` already has the school's public calendar URL and the Pacific
timezone, so unless something has changed there is nothing to edit.

### 3. Start it

```powershell
docker compose up -d --build
```

Open <http://localhost:8080> to check it. That is the whole application — the
rest is turning the PC into a kiosk.

### 4. Lock the PC down

Open PowerShell **as Administrator**, in the project folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\Install-Kiosk.ps1
```

That one script:

- disables the touchscreen (the display is information-only),
- stops the PC sleeping and the screen blanking,
- silences notification toasts,
- registers a task that launches the display full screen at logon,
- registers a watchdog that relaunches it every 5 minutes if it has died,
- registers a 3:30am reboot so Windows Update never interrupts the school day.

Add `-KeepTouch` if you want to leave touch enabled, or `-Browser Chrome` to use
Chrome instead of Edge.

### 5. Two things the script cannot do for you

1. **Docker Desktop → Settings → General → "Start Docker Desktop when you log in".**
   Without this the container will not be running when the display starts.
2. **Automatic sign-in.** Run `netplwiz`, untick *Users must enter a user name and
   password*, and enter the account's password. Otherwise a reboot leaves the panel
   sitting on the lock screen.

Then reboot. The display should come up on its own.

---

## Day-to-day

| I want to… | Do this |
|---|---|
| Start it now without rebooting | `schtasks /run /tn SchoolScheduleKiosk` |
| Get out of kiosk mode | `Alt+F4`, or `Ctrl+Alt+Del` → Task Manager |
| Change the wording or colours | Edit `config/theme.json`, then `docker compose restart` |
| Check an upcoming day | Open `http://localhost:8080/?date=2026-09-18` |
| See the board outside school hours | Same thing — `?date=` never goes into rest mode |
| Change the rest hours | Edit `rest` in `config/theme.json` |
| See what the app thinks is wrong | `http://localhost:8080/healthz` |
| Read the logs | `docker compose logs -f` |
| Update after a code change | `git pull` then `docker compose up -d --build` |
| Undo the kiosk setup | `.\windows\Uninstall-Kiosk.ps1` as Administrator |

Nothing needs a rebuild for branding changes — `config/theme.json` and
`public/assets/` are mounted into the container, so a restart is enough.

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
point `logo.image` at it and `docker compose restart` — no rebuild. Keep a PNG
in `logo.fallback`: it is what renders if the display ever runs a browser
without AVIF support.

---

## Full lockdown (optional)

The kiosk scripts stop the display being *disturbed*. If the panel is somewhere
students can reach the keyboard, Windows can lock it down properly with
**Assigned Access**:

> Settings → Accounts → Other users → Set up a kiosk

Point it at Microsoft Edge in kiosk mode with `http://localhost:8080` as the
start URL. That account can then run nothing else at all. It replaces step 4
above rather than adding to it — Docker Desktop must be running under a
different account, or set to start as a service.

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
   (Docker)       ──►  /api/theme      branding
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
| `windows/` | Kiosk setup scripts |
| `src/format.js` | Tidies event names, applies location rules |
| `tools/demo-feed.mjs` | Fake calendar for testing |
| `tools/format-test.mjs` | Checks the name tidying (`node tools/format-test.mjs`) |
