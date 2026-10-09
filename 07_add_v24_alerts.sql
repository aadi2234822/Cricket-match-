-- ============================================================
-- v24.1: PRE-MATCH ALERTS on Telegram and/or WhatsApp (before each match starts)
-- Run AFTER add_v24_automation.sql (needs app_settings, pg_cron, pg_net). Safe to run again.
-- Telegram uses the bot token + chat ID saved in Admin tools. WhatsApp uses the free CallMeBot API (unofficial).
-- Time zone: Asia/Kolkata.
-- ============================================================
create table if not exists public.alert_log (
  match_id  uuid not null,
  start_key text not null,
  kind      text not null,
  sent_at   timestamptz not null default now(),
  primary key (match_id, start_key, kind)
);
alter table public.alert_log enable row level security;   -- no policies: internal only

-- Sends one text to the enabled channels; returns what happened
create or replace function public.alert_send(p_txt text) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare tok text; chat text; wph text; wkey text; res text := '';
        tgon boolean := coalesce((select value from public.app_settings where key = 'al_tg'), '0') = '1';
        waon boolean := coalesce((select value from public.app_settings where key = 'al_wa'), '0') = '1';
begin
  select value into tok  from public.app_settings where key = 'tg_token';
  select value into chat from public.app_settings where key = 'tg_chat';
  select value into wph  from public.app_settings where key = 'al_wa_phone';
  select value into wkey from public.app_settings where key = 'al_wa_key';
  if tgon then
    if tok is null or chat is null then res := res || 'Telegram: token/chat ID missing. ';
    else
      perform net.http_post(url := 'https://api.telegram.org/bot' || tok || '/sendMessage',
        headers := '{"Content-Type":"application/json"}'::jsonb,
        body := jsonb_build_object('chat_id', chat, 'text', p_txt));
      res := res || 'Telegram sent. ';
    end if;
  end if;
  if waon then
    if coalesce(wph,'') = '' or coalesce(wkey,'') = '' then res := res || 'WhatsApp: number/API key missing. ';
    else
      perform net.http_get(url := 'https://api.callmebot.com/whatsapp.php',
        params := jsonb_build_object('phone', wph, 'text', p_txt, 'apikey', wkey));
      res := res || 'WhatsApp sent. ';
    end if;
  end if;
  return coalesce(nullif(res, ''), 'No channel enabled.');
end; $$;

-- Runs every 5 minutes: alerts for matches starting within the chosen lead time (once per match start time)
create or replace function public.send_prematch_alerts() returns text
language plpgsql security definer set search_path = public, extensions as $$
declare tz text := 'Asia/Kolkata'; rec record; txt text; res text; n int := 0;
        lead int := coalesce((select value from public.app_settings where key = 'al_lead'), '60')::int;
begin
  for rec in
    select m.*, ((m.match_date + m.match_time) at time zone tz) as start_ts
    from public.matches m
    where m.match_time is not null
      and coalesce(m.status, 'Scheduled') in ('Scheduled', 'Recording')
      and ((m.match_date + m.match_time) at time zone tz) > now()
      and ((m.match_date + m.match_time) at time zone tz) <= now() + make_interval(mins => lead)
      and not exists (select 1 from public.alert_log a
                      where a.match_id = m.id and a.kind = 'prematch'
                        and a.start_key = m.match_date::text || ' ' || m.match_time::text)
    order by 2
  loop
    txt := 'Match starting in ' || greatest(1, round(extract(epoch from (rec.start_ts - now())) / 60))::int || ' min' || E'\n'
        || left(rec.match_time::text, 5) || ' - ' || rec.match || ' (' || rec.series || ')'
        || case when rec.camera <> ''           then E'\nCamera: '   || rec.camera else '' end
        || case when rec.operator <> ''         then E'\nOperator: ' || split_part(rec.operator, '@', 1) else '' end
        || case when rec.stream_platforms <> '' then E'\nLive on: '   || rec.stream_platforms else '' end
        || case when rec.stream_link <> ''      then E'\n'           || rec.stream_link else '' end;
    res := public.alert_send(txt);
    if res like '%sent.%' then          -- log only when a channel really sent it, so nothing is lost if Telegram is not ready yet
      insert into public.alert_log(match_id, start_key, kind)
        values (rec.id, rec.match_date::text || ' ' || rec.match_time::text, 'prematch');
      n := n + 1;
    end if;
  end loop;
  delete from public.alert_log where sent_at < now() - interval '7 days';
  return 'alerts sent: ' || n;
end; $$;

create or replace function public.save_alerts(p_lead int, p_tg boolean, p_wa_phone text, p_wa_key text, p_wa_on boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'admin only'; end if;
  insert into public.app_settings values ('al_lead', least(720, greatest(5, coalesce(p_lead, 60)))::text)
    on conflict (key) do update set value = excluded.value;
  insert into public.app_settings values ('al_tg', case when p_tg then '1' else '0' end)
    on conflict (key) do update set value = excluded.value;
  insert into public.app_settings values ('al_wa', case when p_wa_on then '1' else '0' end)
    on conflict (key) do update set value = excluded.value;
  insert into public.app_settings values ('al_wa_phone', regexp_replace(coalesce(p_wa_phone, ''), '[^0-9]', '', 'g'))
    on conflict (key) do update set value = excluded.value;
  if coalesce(p_wa_key, '') <> '' then
    insert into public.app_settings values ('al_wa_key', p_wa_key) on conflict (key) do update set value = excluded.value;
  end if;
  perform cron.unschedule(jobid) from cron.job where jobname = 'cmm_prematch';
  if p_tg or p_wa_on then
    perform cron.schedule('cmm_prematch', '*/5 * * * *', 'select public.send_prematch_alerts()');
  end if;
end; $$;

create or replace function public.get_alerts() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'admin only'; end if;
  return jsonb_build_object(
    'lead',       coalesce((select value from public.app_settings where key = 'al_lead'), '60')::int,
    'tg',         coalesce((select value from public.app_settings where key = 'al_tg'), '0') = '1',
    'wa',         coalesce((select value from public.app_settings where key = 'al_wa'), '0') = '1',
    'wa_phone',   coalesce((select value from public.app_settings where key = 'al_wa_phone'), ''),
    'wa_key_set', exists (select 1 from public.app_settings where key = 'al_wa_key'));
end; $$;

create or replace function public.send_alert_test() returns text
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'admin only'; end if;
  return public.alert_send('Test alert from Cricket Match Manager - pre-match alerts are working.');
end; $$;

grant execute on function public.save_alerts(int, boolean, text, text, boolean) to authenticated;
grant execute on function public.get_alerts() to authenticated;
grant execute on function public.send_alert_test() to authenticated;

-- Internal functions must NOT be callable from the browser / public API
revoke execute on function public.alert_send(text)            from public, anon, authenticated;
revoke execute on function public.send_prematch_alerts()      from public, anon, authenticated;
revoke execute on function public.send_telegram_schedule()    from public, anon, authenticated;
