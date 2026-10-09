-- ============================================================
-- v24 CORE: operators, live-stream platforms, activity log, backups,
-- storage health, share links.
-- Run ONCE in Supabase SQL Editor AFTER: add_status_column.sql, add_v21_columns.sql,
-- add_camera_column.sql and add_roles.sql. Safe to run again.
-- ============================================================

-- 1) New match columns
alter table public.matches add column if not exists operator         text not null default '';
alter table public.matches add column if not exists stream_platforms text not null default '';
alter table public.matches add column if not exists stream_link      text not null default '';

-- 2) Users with only "Status & checklist" may also set camera, operator and live-stream fields
create or replace function public.matches_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare keep text[] := array['status','recorded','uploaded','checklist','video_link','recording_remarks',
                             'camera','operator','stream_platforms','stream_link'];
begin
  if auth.uid() is null then return new; end if;
  if public.has_perm('edit') then return new; end if;
  if public.has_perm('status') then
    if (to_jsonb(new) - keep) is distinct from (to_jsonb(old) - keep) then
      raise exception 'You may only change status, checklist, camera, operator, live-stream fields and remarks.';
    end if;
    return new;
  end if;
  raise exception 'You do not have permission to edit matches.';
end; $$;

-- 3) Team list (approved users) for the Operator dropdown
create or replace function public.team_list() returns table(email text)
language sql stable security definer set search_path = public as $$
  select p.email from public.profiles p
  where p.approved and p.email is not null and public.has_perm('view')
  order by p.email;
$$;
grant execute on function public.team_list() to authenticated;

-- 4) Activity log (admins read it)
create table if not exists public.activity_log (
  id         bigint generated always as identity primary key,
  at         timestamptz not null default now(),
  user_email text,
  action     text not null,
  match_id   uuid,
  match_name text,
  details    jsonb
);
alter table public.activity_log enable row level security;
drop policy if exists "log admin read" on public.activity_log;
create policy "log admin read" on public.activity_log for select to authenticated using (public.is_admin());

create or replace function public.log_match_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare who text; d jsonb;
begin
  select email into who from public.profiles where user_id = auth.uid();
  if tg_op = 'INSERT' then
    insert into public.activity_log(user_email, action, match_id, match_name, details)
    values (who, 'added', new.id, new.match, jsonb_build_object('series', new.series, 'date', new.match_date));
    return new;
  elsif tg_op = 'DELETE' then
    insert into public.activity_log(user_email, action, match_id, match_name, details)
    values (who, 'deleted', old.id, old.match, jsonb_build_object('series', old.series, 'date', old.match_date));
    return old;
  else
    select coalesce(jsonb_object_agg(n.key, jsonb_build_object('old', o.value, 'new', n.value)), '{}'::jsonb)
      into d
      from jsonb_each(to_jsonb(new)) n join jsonb_each(to_jsonb(old)) o on o.key = n.key
      where n.value is distinct from o.value;
    if d <> '{}'::jsonb then
      insert into public.activity_log(user_email, action, match_id, match_name, details)
      values (who, 'updated', new.id, new.match, d);
    end if;
    return new;
  end if;
end; $$;
drop trigger if exists matches_log_trg on public.matches;
create trigger matches_log_trg after insert or update or delete on public.matches
  for each row execute function public.log_match_change();

create or replace function public.log_profile_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare who text; d jsonb;
begin
  select email into who from public.profiles where user_id = auth.uid();
  select coalesce(jsonb_object_agg(n.key, jsonb_build_object('old', o.value, 'new', n.value)), '{}'::jsonb)
    into d
    from jsonb_each(to_jsonb(new)) n join jsonb_each(to_jsonb(old)) o on o.key = n.key
    where n.value is distinct from o.value;
  if d <> '{}'::jsonb then
    insert into public.activity_log(user_email, action, match_name, details)
    values (who, 'permissions', new.email, d);
  end if;
  return new;
end; $$;
drop trigger if exists profiles_log_trg on public.profiles;
create trigger profiles_log_trg after update on public.profiles
  for each row execute function public.log_profile_change();

-- 5) Backups (snapshots of all matches, last 8 kept)
create table if not exists public.backups (
  id         bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  row_count  int,
  data       jsonb not null
);
alter table public.backups enable row level security;
drop policy if exists "backups admin read" on public.backups;
create policy "backups admin read" on public.backups for select to authenticated using (public.is_admin());

create or replace function public.make_backup() returns bigint
language plpgsql security definer set search_path = public as $$
declare bid bigint;
begin
  if auth.uid() is not null and not public.is_admin() then raise exception 'admin only'; end if;
  insert into public.backups(row_count, data)
    select count(*), coalesce(jsonb_agg(to_jsonb(m)), '[]'::jsonb) from public.matches m
    returning id into bid;
  delete from public.backups where id not in (select id from public.backups order by created_at desc limit 8);
  delete from public.activity_log where at < now() - interval '90 days';
  return bid;
end; $$;
grant execute on function public.make_backup() to authenticated;

-- 6) Storage / health card
create or replace function public.db_health() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'admin only'; end if;
  return jsonb_build_object(
    'db_bytes', pg_database_size(current_database()),
    'matches',  (select count(*) from public.matches),
    'log_rows', (select count(*) from public.activity_log),
    'backups',  (select count(*) from public.backups));
end; $$;
grant execute on function public.db_health() to authenticated;

-- 7) Read-only share links
create table if not exists public.shares (
  token      text primary key,
  series     text,
  label      text,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
alter table public.shares enable row level security;
drop policy if exists "shares admin all" on public.shares;
create policy "shares admin all" on public.shares for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create or replace function public.shared_schedule(p_token text)
returns table(match_date date, match_time time, series text, "match" text, odi_t20 text,
              stream_platforms text, stream_link text)
language sql stable security definer set search_path = public as $$
  select m.match_date, m.match_time, m.series, m."match", m.odi_t20, m.stream_platforms, m.stream_link
  from public.matches m
  join public.shares s on s.token = p_token and (s.series is null or s.series = '' or s.series = m.series)
  where m.match_date >= current_date - 1 and coalesce(m.status,'Scheduled') <> 'Cancelled'
  order by m.match_date, m.match_time;
$$;
grant execute on function public.shared_schedule(text) to anon, authenticated;
