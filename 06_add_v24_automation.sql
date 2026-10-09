-- ============================================================
-- v24 AUTOMATION: weekly auto-backup + daily Telegram schedule.
-- Run AFTER add_v24_core.sql. Needs the pg_cron and pg_net extensions
-- (Supabase Dashboard > Database > Extensions: enable "pg_cron" and "pg_net" if the lines below fail).
-- Time zone used for "today" and the send time: Asia/Kolkata (change 'Asia/Kolkata' below if needed).
-- ============================================================
create extension if not exists pg_cron;
create extension if not exists pg_net;

create table if not exists public.app_settings (key text primary key, value text);
alter table public.app_settings enable row level security;   -- no policies: only the functions below can touch it

-- Weekly backup: Sunday 21:00 UTC
select cron.schedule('cmm_weekly_backup', '0 21 * * 0', 'select public.make_backup()');

create or replace function public.send_telegram_schedule() returns text
language plpgsql security definer set search_path = public, extensions as $$
declare tok text; chat text; tz text := 'Asia/Kolkata'; txt text; today date; rec record; n int := 0;
begin
  select value into tok  from public.app_settings where key = 'tg_token';
  select value into chat from public.app_settings where key = 'tg_chat';
  if tok is null or chat is null then return 'Telegram is not configured'; end if;
  today := (now() at time zone tz)::date;
  txt := 'Matches today (' || to_char(today, 'DD Mon YYYY') || ')' || E'\n';
  for rec in select * from public.matches
             where match_date = today and coalesce(status,'Scheduled') not in ('Cancelled','Postponed','Abandoned')
             order by match_time loop
    n := n + 1;
    txt := txt || E'\n' || left(rec.match_time::text, 5) || ' - ' || rec.match || ' (' || rec.series || ')'
        || case when rec.camera <> ''           then ' | ' || rec.camera else '' end
        || case when rec.operator <> ''         then ' | ' || split_part(rec.operator, '@', 1) else '' end
        || case when rec.stream_platforms <> '' then ' | Live: ' || rec.stream_platforms else '' end;
  end loop;
  if n = 0 then txt := txt || E'\nNo matches today.'; end if;
  perform net.http_post(
    url     := 'https://api.telegram.org/bot' || tok || '/sendMessage',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body    := jsonb_build_object('chat_id', chat, 'text', txt));
  return 'sent (' || n || ' matches)';
end; $$;

create or replace function public.save_telegram(p_token text, p_chat text, p_time text, p_enabled boolean)
returns void language plpgsql security definer set search_path = public as $$
declare h int; m int; utc timestamp; tz text := 'Asia/Kolkata';
begin
  if not public.is_admin() then raise exception 'admin only'; end if;
  if coalesce(p_token,'') <> '' then
    insert into public.app_settings values ('tg_token', p_token) on conflict (key) do update set value = excluded.value;
  end if;
  insert into public.app_settings values ('tg_chat', coalesce(p_chat,''))  on conflict (key) do update set value = excluded.value;
  insert into public.app_settings values ('tg_time', coalesce(p_time,'08:00')) on conflict (key) do update set value = excluded.value;
  insert into public.app_settings values ('tg_on', case when p_enabled then '1' else '0' end) on conflict (key) do update set value = excluded.value;
  perform cron.unschedule(jobid) from cron.job where jobname = 'cmm_telegram';
  if p_enabled then
    h := split_part(p_time, ':', 1)::int;  m := split_part(p_time, ':', 2)::int;
    utc := ((current_date::timestamp + make_interval(hours => h, mins => m)) at time zone tz) at time zone 'UTC';
    perform cron.schedule('cmm_telegram',
      extract(minute from utc)::int || ' ' || extract(hour from utc)::int || ' * * *',
      'select public.send_telegram_schedule()');
  end if;
end; $$;

create or replace function public.get_telegram() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'admin only'; end if;
  return jsonb_build_object(
    'chat',      (select value from public.app_settings where key = 'tg_chat'),
    'time',      coalesce((select value from public.app_settings where key = 'tg_time'), '08:00'),
    'enabled',   coalesce((select value from public.app_settings where key = 'tg_on'), '0') = '1',
    'token_set', exists (select 1 from public.app_settings where key = 'tg_token'));
end; $$;

create or replace function public.send_telegram_test() returns text
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'admin only'; end if;
  return public.send_telegram_schedule();
end; $$;

grant execute on function public.save_telegram(text,text,text,boolean) to authenticated;
grant execute on function public.get_telegram() to authenticated;
grant execute on function public.send_telegram_test() to authenticated;


-- Find the Telegram chat ID automatically (2 steps because pg_net sends requests after the transaction ends)
create or replace function public.telegram_detect_start() returns bigint
language plpgsql security definer set search_path = public, extensions as $$
declare tok text; req bigint;
begin
  if not public.is_admin() then raise exception 'admin only'; end if;
  select value into tok from public.app_settings where key = 'tg_token';
  if tok is null then raise exception 'Save the bot token first'; end if;
  req := net.http_get(url := 'https://api.telegram.org/bot' || tok || '/getUpdates');
  insert into public.app_settings values ('tg_detect_req', req::text)
    on conflict (key) do update set value = excluded.value;
  return req;
end; $$;

create or replace function public.telegram_detect_finish() returns text
language plpgsql security definer set search_path = public, extensions as $$
declare req bigint; resp record; upd jsonb; ch jsonb; grp jsonb; prv jsonb; best jsonb;
begin
  if not public.is_admin() then raise exception 'admin only'; end if;
  select value::bigint into req from public.app_settings where key = 'tg_detect_req';
  if req is null then return 'Press the button again.'; end if;
  select * into resp from net._http_response where id = req;
  if not found then return 'Telegram has not answered yet. Wait a few seconds and press again.'; end if;
  if resp.status_code is distinct from 200 then
    return 'Telegram error ' || coalesce(resp.status_code::text, '?') || ': '
           || left(coalesce(resp.content, resp.error_msg, ''), 150) || ' (check the bot token)';
  end if;
  for upd in select value from jsonb_array_elements(coalesce((resp.content::jsonb) -> 'result', '[]'::jsonb)) loop
    ch := coalesce(upd -> 'message' -> 'chat', upd -> 'my_chat_member' -> 'chat',
                   upd -> 'edited_message' -> 'chat', upd -> 'channel_post' -> 'chat');
    if ch is not null then
      if ch ->> 'type' in ('group', 'supergroup') then grp := ch; else prv := ch; end if;   -- latest update wins
    end if;
  end loop;
  best := coalesce(grp, prv);
  if best is null then
    return 'No chat found yet. Add the bot to your group, send a message there, then press the button again.';
  end if;
  insert into public.app_settings values ('tg_chat', best ->> 'id')
    on conflict (key) do update set value = excluded.value;
  return 'Chat ID saved: ' || (best ->> 'id') || ' (' || coalesce(best ->> 'title', best ->> 'first_name', 'chat') || ')';
end; $$;

grant execute on function public.telegram_detect_start() to authenticated;
grant execute on function public.telegram_detect_finish() to authenticated;
