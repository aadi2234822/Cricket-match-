CRICKET MATCH MANAGER - ONLINE SUPABASE VERSION

1. Extract ZIP and open folder in Acode.
2. Before using the app, open Supabase Dashboard -> SQL Editor.
3. Open setup_database.sql from this ZIP and run ALL SQL.
4. In Supabase Authentication, configure Email provider as desired.
5. Open index.html using Acode Preview/browser.
6. Click Create account, enter email/password.
7. Login and start adding matches.

ODI -> Expected Overs 100
T20 -> Expected Overs 40

The app stores each user's records online in Supabase. Row Level Security means a logged-in user can only read/change their own records.

IMPORTANT:
- The publishable key is intended for frontend use with RLS enabled.
- Never put a Supabase service_role/secret key in this app.
- Excel import/export uses SheetJS CDN, so internet is needed for those functions.


EXCEL FORMAT: Download Excel now uses your uploaded September 2026 workbook as the template, preserving its sheet name, column widths, header formatting, Arial font, borders and layout while replacing the data rows with online database data.


NEW FEATURES:
- Bulk Add: ek series + ODI/T20 ek baar bharo, phir har date ke neeche jitne match ho utni match lines add karo (+ Match line). Dusri date ke liye + Add Date. Save All Matches se sab ek saath save hote hain.
- Date hamesha dd-mm-yyyy, Time hamesha AM/PM me dikhta hai (app aur Excel dono me).
- Recording Remarks ka border yellow hai (form, table aur Excel).
- Excel export ab xlsx-js-style use karta hai taaki colors/borders sahi save hon.
