CRICKET MATCH MANAGER ONLINE - VERSION 22

VERSION 24.1 - PRE-MATCH ALERTS ON TELEGRAM / WHATSAPP
- Admin tools > "Pre-match alerts": choose how long before the match (15 min / 30 min / 1 h / 2 h) and tick Telegram and/or WhatsApp.
  Every 5 minutes the database sends one alert per match start time (with camera, operator, live platform and link).
  Only matches with status Scheduled or Recording get alerts. If a match is rescheduled it gets a new alert.
- Run add_v24_alerts.sql (after add_v24_automation.sql). It also blocks the internal send functions from public API calls.
- TELEGRAM: create a bot with @BotFather, put the bot in your team GROUP (everyone in the group sees the alert), save the bot token and
  chat ID in the Telegram box first, then tick Telegram in Pre-match alerts.
- WHATSAPP (free, via CallMeBot, an unofficial third-party service): open https://www.callmebot.com/blog/free-api-whatsapp-messages/ ,
  add the CallMeBot contact, send "I allow callmebot to send me messages" from your WhatsApp, and it replies with your personal API key.
  Enter your number (country code, no +) and the key. One key = one WhatsApp number. Not suitable for large teams or guaranteed delivery.
  The official WhatsApp Business API needs a Meta business account and paid, pre-approved templates.

VERSION 24 - ADVANCED PACK
In the app (works after add_v24_core.sql):
- Live stream platforms per match (YouTube, Facebook, JioHotstar, Sony LIV, FanCode, Star Sports, Willow, Other) + stream link.
  Tap "+ add" in the Live on column. Filter by platform. Included in Excel, reminders text, Telegram and share page.
- Generate title & description for YouTube (button in the same box, copied to clipboard).
- Operator assignment (who records which match) and "My matches" filter. "Reminders only for my matches" option.
- Upload deadline tracker: choose target hours after match end; late matches show a clock mark and go to Needs Attention.
- Camera Planner: day timeline per camera, and "Suggest cameras" auto-assigns free cameras without clashes.
- Analytics: matches per month, by status, camera, operator, live platform, upload completion.
- Calendar export (.ics) for Google / Apple Calendar.
Admin tools (bottom of page, admins only):
- Storage & health (size vs 500 MB), Activity log (who changed what, old and new value), Backups (now + weekly),
  Telegram daily schedule, read-only Share links (share.html?t=TOKEN, no login needed for viewers).
NOT included (needs a server and paid/external keys): push notifications with the app fully closed, automatic fixture
sync with a hidden API key, and AI photo-to-matches. These can be a separate backend pack.

SQL ORDER: add_status_column > add_v21_columns > add_camera_column > add_roles > add_v24_core > add_v24_automation > add_v24_alerts (optional).
add_v24_automation.sql needs the pg_cron and pg_net extensions and uses India time (Asia/Kolkata).
Telegram: create a bot with @BotFather, send it a message, get your chat id, then fill the Telegram box in Admin tools.
The bot token is stored in the database and is only reachable by admin-only functions.
Keep-alive: .github/workflows/keepalive.yml pings Supabase every 3 days from GitHub Actions (add 2 secrets, see file).

VERSION 23 - CAMERA PER MATCH
- New "Camera" field (Camera 1 ... Camera 8) in the match form and as a dropdown column in the table, so you can
  see at a glance which camera each match is recorded on. Change the number of cameras with CAM_COUNT in index.html.
- Filter the table by camera (or "No camera set"). Select many matches and use "Set camera" to assign in bulk.
- Overlap warning is camera-aware: two overlapping matches on DIFFERENT cameras are fine; same camera or a camera
  not set shows a warning.
- Camera shows in reminders and the Needs Attention list, and in Excel export/import (Camera column at the end).
- Users with "Status & checklist" permission can also set the camera.
UPGRADE: run add_camera_column.sql once in Supabase SQL Editor, upload all files, reload twice.

VERSION 22.2 - USERNAME LOGIN (stricter usernames, clearer errors)
- The login box now accepts a plain username (3-20 letters or numbers only; no spaces, dots or symbols) or an email address.
  Usernames are stored internally as username@cricketmatch.app (no email is ever sent to it).
- REQUIRED in Supabase for username accounts: Authentication > Sign In / Providers > Email > turn OFF "Confirm email".
  (Admin approval replaces email confirmation.) Also make sure "Allow new users to sign up" is ON.
- If Supabase rejects the internal address as invalid, change USERNAME_DOMAIN near the top of the roles script in
  index.html to a domain you own, BEFORE creating users.
- Admin can also add users directly: Supabase > Authentication > Users > Add user (tick Auto Confirm User).

NEW IN VERSION 22 - ADMIN / USER LOGIN WITH PERMISSIONS
- One shared match list for the whole team. Everyone logs in with their own email and password.
- Roles: Admin (full access + user management) and User (only what the admin allows).
- New sign-ups see a "Waiting for approval" screen until an admin approves them.
- Admin panel (bottom of the page, admins only): approve or block users, make someone admin, pick a preset
  (Viewer, Recorder, Editor, Full) or tick permissions one by one:
    View matches | Add / import | Edit all fields | Status & checklist | Delete | Export / backup
- Permissions are enforced by the database (Supabase RLS + triggers), not just hidden in the page. A user with only
  "Status & checklist" can change status, checklist, upload link and remarks, nothing else.
- Export / backup is hidden in the page, but anyone who can View could still copy data by other means.
- Delete All is admin only. An admin cannot demote or block their own account.
- Deleting a user in Supabase no longer deletes the matches they created.

UPGRADE STEPS (v21 -> v22)
1. Run add_roles.sql once in Supabase SQL Editor (after add_status_column.sql and add_v21_columns.sql).
   The account that owns the most existing matches becomes the first admin. Everyone else becomes "pending".
2. Upload ALL files to your hosting (index.html and sw.js changed) and reload twice.
3. Log in as the admin, open the Admin panel, approve each user and choose a preset.
Until add_roles.sql is run the app shows a notice and behaves like v21.

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
