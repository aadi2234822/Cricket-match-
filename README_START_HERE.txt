CRICKET MATCH MANAGER - v25 (Telegram ready)
=============================================
Teen folder hain:

1) website/            -> sirf ye files apni hosting par upload karo (index.html, share.html, sw.js, manifest.json, icons).
2) supabase_sql/       -> ye files SIRF Supabase SQL Editor mein chalani hain. Inhe hosting par upload MAT karo.
                          08_PRIVATE_telegram_seed.sql mein aapka bot token hai - kisi ko mat bhejna.
3) github_keepalive/   -> optional: Supabase ko pause hone se bachane ka GitHub workflow (file ke andar steps likhe hain).

SUPABASE MEIN SQL KA ORDER (jo pehle chal chuka hai use dobara chalane se dikkat nahi, safe hai)
  01_add_status_column.sql
  02_add_v21_columns.sql
  03_add_camera_column.sql
  04_add_roles.sql
  05_add_v24_core.sql
  06_add_v24_automation.sql   (pehle Database > Extensions mein pg_cron aur pg_net ON karo)
  07_add_v24_alerts.sql
  08_PRIVATE_telegram_seed.sql   (token save + alerts ON)
Naya (khali) Supabase project ho to 00_fresh_install_all_in_one.sql chalao, phir seedha 06, 07, 08.
extra/ folder ke files purane hain, normally chahiye nahi.

TELEGRAM - AB BAS YE KARNA HAI
1. Telegram group mein bot @MyCricketAlertbot ko member ki tarah add karo (group mein "2 members" dikhna chahiye).
2. Group mein koi message bhejo, jaise /start@MyCricketAlertbot
3. App kholo > Admin tools > Telegram box > "Find chat ID automatically" dabao. 6 second baad "Chat ID saved" aana chahiye.
4. "Send test alert" dabao (Pre-match alerts box). Group mein test message aana chahiye.
Bas. Iske baad har match se 1 ghanta pehle (Admin tools mein badal sakte ho) group mein alert aayega.

NOTE
- Token aapne chat mein dikha diya tha. Safe rehna hai to BotFather mein /revoke karke naya token lo, phir app ke Telegram box mein
  naya token paste karke Save karo (08 file dobara chalane ki zaroorat nahi).
- Features ki puri list: website_README_features.txt
- Ye SQL aur code maine test nahi chalaye (test Postgres nahi tha). Pehle apne Supabase ki copy par try karo.
