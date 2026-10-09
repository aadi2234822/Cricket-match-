CRICKET MATCH MANAGER ONLINE - VERSION 21

NEW IN VERSION 21
- Overlap warning: saving a single or bulk match that overlaps another active match asks for confirmation.
  Clashes in upcoming matches show a warning mark in the table and in the Needs Attention panel.
  Match length is estimated (T20 = 3.5 h, ODI = 8 h). Postponed / Abandoned / Cancelled are ignored.
- Multi-select: tick rows (or "select all shown") to set status, shift dates by N days (written to reschedule
  history) or delete many matches at once.
- Undo: a 12-second Undo button appears after delete, delete all, bulk actions, status changes and checklist saves.
  Undoing a delete also restores that match's reschedule history.
- Checklist + upload link: per match, tap the "n/5" button (Recorded, Trimmed, Thumbnail, Title, Uploaded) and
  paste the video link (http/https only).
- Excel: exports now include Status and Upload Link columns (added at the end, existing columns unchanged).
  Import reads Status and Upload Link when present. JSON backup/restore carries status, link and checklist.

UPGRADE STEPS (v20 -> v21)
1. Run add_v21_columns.sql once in Supabase SQL Editor (add_status_column.sql from v20 must already be run).
2. Upload ALL files to your hosting, replacing the old ones (index.html and sw.js changed).
3. Reload the app twice so the new service worker takes over.

NEW IN VERSION 20
- Status workflow: Scheduled > Recording > Recorded > Editing > Uploaded, plus Postponed / Abandoned / Cancelled.
  Change status straight from the table dropdown. Recorded/Uploaded fields, dashboard and Excel stay in sync.
  Cancelled / Postponed / Abandoned matches are excluded from dashboard counts. Filter the table by status.
- Needs Attention panel: matches starting within 24h, matches whose time has passed but are still Scheduled,
  and recorded matches waiting for upload more than a day. Tab title shows the count.
- Reminders: browser notifications before each match (15 min to 6 h), "starting now", and a daily pending summary.
  They fire while the app is open or installed and running. True push while fully closed would need a server.
- PWA: install to the home screen (manifest.json, sw.js, icons), app shell works offline, and the last synced
  matches are shown read-only when offline. Needs https or localhost; Acode's embedded browser may not support it.

UPGRADE STEPS (v19 -> v20)
1. Run add_status_column.sql once in Supabase SQL Editor (existing rows are back-filled from Recorded/Uploaded).
2. Upload ALL files (index.html, manifest.json, sw.js, three icon-*.png) to the same folder on your hosting.
3. Open the app, tap "Enable reminders" and allow notifications. Use "Install app" in the header if shown.

Features preserved:
- Supabase email/password login and per-user database access (RLS)
- Match entry, edit, delete, bulk add and row-wise match table
- ODI expected overs 100; T20 expected overs 40
- Existing CricAPI series search/fetch feature
- Month-wise Excel downloads and Excel import
- Recording dashboard counters
- Upcoming match calendar with countdown based on this device's local time
- Date-range Excel report
- JSON backup and restore (duplicates and invalid records are skipped)
- Duplicate checks during single entry and bulk add
- Reschedule history when an existing match date/time is changed
- Search, mobile horizontal table scrolling and normal Remarks column styling

IMPORTANT SETUP
1. Extract this ZIP.
2. Open Supabase Dashboard -> SQL Editor.
3. Run setup_reschedule_history.sql once to enable the reschedule history feature.
   (The same SQL is also appended to setup_database.sql; existing users do not need to recreate their matches table.)
4. Open index.html through your normal web hosting/local web server and sign in.
5. Keep Supabase Row Level Security enabled. Never add a Supabase service-role key to this HTML file.

AUTO FETCH NOTE
The existing auto-fetch tool in this version uses CricAPI (cricketdata.org) and requires a CricAPI key. RapidAPI's screenshot showed an MCP configuration and endpoint names, but did not include the REST endpoint URL, parameters, or JSON response. Therefore this ZIP does not pretend to have a verified RapidAPI integration. Once the exact REST endpoint and sample response are provided, RapidAPI can be added safely through a server-side proxy/Edge Function; do not expose the RapidAPI secret in browser code.

DOWNLOAD NOTE
This app uses browser file downloads for Excel and JSON. If Acode's embedded browser reports that blob URLs are unsupported, open the app in Chrome or another full browser to download files.
