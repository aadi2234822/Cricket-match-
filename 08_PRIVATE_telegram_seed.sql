-- ============================================================
-- PRIVATE FILE - contains your Telegram bot token.
-- Run it ONLY in Supabase SQL Editor (after 07). NEVER upload this folder to your website hosting, GitHub or share it.
-- It saves the bot token, turns ON Telegram pre-match alerts (1 hour before) and starts the 5-minute alert job.
-- The chat ID is found later from the app: Admin tools > Telegram > "Find chat ID automatically".
-- ============================================================
insert into public.app_settings (key, value) values
  ('tg_token', '8752866190:AAFJAlcWTpNt-YjhaBqGrmPEOPaXtaDZVw4'),
  ('al_lead',  '60'),
  ('al_tg',    '1'),
  ('al_wa',    '0'),
  ('tg_time',  '08:00'),
  ('tg_on',    '0')
on conflict (key) do update set value = excluded.value;

select cron.unschedule(jobid) from cron.job where jobname = 'cmm_prematch';
select cron.schedule('cmm_prematch', '*/5 * * * *', 'select public.send_prematch_alerts()');
