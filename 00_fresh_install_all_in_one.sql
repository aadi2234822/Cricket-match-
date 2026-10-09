-- Run this SQL in Supabase Dashboard -> SQL Editor
create extension if not exists pgcrypto;

create table if not exists public.matches (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  format text not null default 'Cricket',
  match_date date not null,
  match_time time,
  series text not null,
  match text not null,
  odi_t20 text not null check (odi_t20 in ('ODI','T20')),
  expected_overs integer not null check (expected_overs in (40,100)),
  recorded text not null default 'Pending' check (recorded in ('Pending','Done')),
  uploaded text not null default 'Pending' check (uploaded in ('Pending','Done')),
  recording_remarks text default '',
  created_at timestamptz not null default now()
);

alter table public.matches enable row level security;

drop policy if exists "Users can view own matches" on public.matches;
create policy "Users can view own matches"
on public.matches for select
to authenticated
using (auth.uid() = user_id);

drop policy if exists "Users can insert own matches" on public.matches;
create policy "Users can insert own matches"
on public.matches for insert
to authenticated
with check (auth.uid() = user_id);

drop policy if exists "Users can update own matches" on public.matches;
create policy "Users can update own matches"
on public.matches for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Users can delete own matches" on public.matches;
create policy "Users can delete own matches"
on public.matches for delete
to authenticated
using (auth.uid() = user_id);

-- Excel import ka original order (same date + same time wali rows) sahi rakhne ke liye:
alter table public.matches add column if not exists seq bigint generated always as identity;

-- Reschedule history (safe to run repeatedly)
create table if not exists public.match_reschedule_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  series text not null default '',
  match_name text not null default '',
  old_date date not null,
  old_time time,
  new_date date not null,
  new_time time,
  changed_at timestamptz not null default now()
);
alter table public.match_reschedule_history enable row level security;
drop policy if exists "Users can view own reschedule history" on public.match_reschedule_history;
create policy "Users can view own reschedule history" on public.match_reschedule_history for select to authenticated using (auth.uid() = user_id);
drop policy if exists "Users can insert own reschedule history" on public.match_reschedule_history;
create policy "Users can insert own reschedule history" on public.match_reschedule_history for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "Users can delete own reschedule history" on public.match_reschedule_history;
create policy "Users can delete own reschedule history" on public.match_reschedule_history for delete to authenticated using (auth.uid() = user_id);

-- v20: status workflow
-- Adds the status workflow: Scheduled > Recording > Recorded > Editing > Uploaded (+ Postponed / Abandoned / Cancelled)
alter table public.matches add column if not exists status text not null default 'Scheduled';
alter table public.matches drop constraint if exists matches_status_check;
alter table public.matches add constraint matches_status_check
  check (status in ('Scheduled','Recording','Recorded','Editing','Uploaded','Postponed','Abandoned','Cancelled'));
-- Backfill existing rows from the old Recorded / Uploaded fields
update public.matches
set status = case when uploaded = 'Done' then 'Uploaded' when recorded = 'Done' then 'Recorded' else 'Scheduled' end
where status = 'Scheduled';

-- v21: upload link + checklist
alter table public.matches add column if not exists video_link text not null default '';
alter table public.matches add column if not exists checklist jsonb not null default '{}'::jsonb;

-- v22: roles & permissions

-- 1) Profiles: one row per user (role, approval, permissions)
create table if not exists public.profiles (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  email      text,
  role       text not null default 'user' check (role in ('admin','user')),
  approved   boolean not null default false,
  can_view   boolean not null default false,
  can_add    boolean not null default false,
  can_edit   boolean not null default false,
  can_status boolean not null default false,
  can_delete boolean not null default false,
  can_export boolean not null default false,
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;

-- 2) Helper functions (security definer so policies can read profiles safely)
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles
                 where user_id = auth.uid() and role = 'admin' and approved);
$$;

create or replace function public.has_perm(p text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select approved and (role = 'admin' or case p
        when 'view'   then can_view
        when 'add'    then can_add
        when 'edit'   then can_edit
        when 'status' then can_status
        when 'delete' then can_delete
        when 'export' then can_export
        else false end)
    from public.profiles where user_id = auth.uid()), false);
$$;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.has_perm(text) to authenticated;

-- 3) New sign-ups get a profile. The very first account becomes admin; everyone else waits for approval.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare first_user boolean;
begin
  select not exists (select 1 from public.profiles where role = 'admin') into first_user;
  insert into public.profiles (user_id, email, role, approved, can_view, can_add, can_edit, can_status, can_delete, can_export)
  values (new.id, new.email, case when first_user then 'admin' else 'user' end,
          first_user, first_user, first_user, first_user, first_user, first_user, first_user)
  on conflict (user_id) do nothing;
  return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- 4) Back-fill profiles for accounts that already exist (pending, no permissions)
insert into public.profiles (user_id, email)
select id, email from auth.users
on conflict (user_id) do nothing;

-- 5) Make the owner of the existing matches (or the oldest account) the admin
update public.profiles
set role = 'admin', approved = true, can_view = true, can_add = true,
    can_edit = true, can_status = true, can_delete = true, can_export = true
where user_id = coalesce(
        (select user_id from public.matches where user_id is not null
         group by user_id order by count(*) desc limit 1),
        (select id from auth.users order by created_at limit 1))
  and not exists (select 1 from public.profiles where role = 'admin');
-- To make someone else admin instead:
--   update public.profiles set role='admin', approved=true, can_view=true, can_add=true, can_edit=true,
--     can_status=true, can_delete=true, can_export=true where email='someone@example.com';

-- 6) Profiles policies: users read their own row, admins read/update everyone
drop policy if exists "profiles read" on public.profiles;
create policy "profiles read" on public.profiles for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
drop policy if exists "profiles admin update" on public.profiles;
create policy "profiles admin update" on public.profiles for update to authenticated
  using (public.is_admin()) with check (public.is_admin());
drop policy if exists "profiles admin delete" on public.profiles;
create policy "profiles admin delete" on public.profiles for delete to authenticated
  using (public.is_admin() and user_id <> auth.uid());

-- Stop an admin from demoting or blocking themselves (would lock everyone out)
create or replace function public.profiles_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and old.user_id = auth.uid() and old.role = 'admin'
     and (new.role <> 'admin' or not new.approved) then
    raise exception 'An admin cannot remove their own admin access.';
  end if;
  return new;
end; $$;
drop trigger if exists profiles_guard_trg on public.profiles;
create trigger profiles_guard_trg before update on public.profiles
  for each row execute function public.profiles_guard();

-- 7) Matches become one shared list, controlled by permissions
drop policy if exists "Users can view own matches"   on public.matches;
drop policy if exists "Users can insert own matches" on public.matches;
drop policy if exists "Users can update own matches" on public.matches;
drop policy if exists "Users can delete own matches" on public.matches;
drop policy if exists "Shared view matches"   on public.matches;
drop policy if exists "Shared insert matches" on public.matches;
drop policy if exists "Shared update matches" on public.matches;
drop policy if exists "Shared delete matches" on public.matches;

create policy "Shared view matches" on public.matches for select to authenticated
  using (public.has_perm('view'));
create policy "Shared insert matches" on public.matches for insert to authenticated
  with check (public.has_perm('add') and (user_id = auth.uid() or public.is_admin()));
create policy "Shared update matches" on public.matches for update to authenticated
  using (public.has_perm('edit') or public.has_perm('status'))
  with check (public.has_perm('edit') or public.has_perm('status'));
create policy "Shared delete matches" on public.matches for delete to authenticated
  using (public.has_perm('delete'));

-- Users with only "Status & checklist" may change just those columns
create or replace function public.matches_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare keep text[] := array['status','recorded','uploaded','checklist','video_link','recording_remarks','camera'];
begin
  if auth.uid() is null then return new; end if;            -- SQL editor / service role
  if public.has_perm('edit') then return new; end if;
  if public.has_perm('status') then
    if (to_jsonb(new) - keep) is distinct from (to_jsonb(old) - keep) then
      raise exception 'You may only change status, checklist, link and remarks.';
    end if;
    return new;
  end if;
  raise exception 'You do not have permission to edit matches.';
end; $$;
drop trigger if exists matches_guard_trg on public.matches;
create trigger matches_guard_trg before update on public.matches
  for each row execute function public.matches_guard();

-- Deleting a user account must NOT delete the shared matches they created
do $$
declare t text; c text;
begin
  foreach t in array array['matches','match_reschedule_history'] loop
    if to_regclass('public.'||t) is null then continue; end if;
    for c in select conname from pg_constraint
             where conrelid = ('public.'||t)::regclass and contype = 'f'
               and confrelid = 'auth.users'::regclass loop
      execute format('alter table public.%I drop constraint %I', t, c);
    end loop;
    execute format('alter table public.%I alter column user_id drop not null', t);
    execute format('alter table public.%I add constraint %I foreign key (user_id) references auth.users(id) on delete set null', t, t||'_user_id_fkey');
  end loop;
end $$;

-- 8) Reschedule history follows the same permissions
do $$ begin
  if to_regclass('public.match_reschedule_history') is not null then
    drop policy if exists "Users can view own reschedule history"   on public.match_reschedule_history;
    drop policy if exists "Users can insert own reschedule history" on public.match_reschedule_history;
    drop policy if exists "Users can delete own reschedule history" on public.match_reschedule_history;
    drop policy if exists "Shared view history"   on public.match_reschedule_history;
    drop policy if exists "Shared insert history" on public.match_reschedule_history;
    drop policy if exists "Shared delete history" on public.match_reschedule_history;
    create policy "Shared view history" on public.match_reschedule_history for select to authenticated
      using (public.has_perm('view'));
    create policy "Shared insert history" on public.match_reschedule_history for insert to authenticated
      with check (public.has_perm('edit') and (user_id = auth.uid() or public.is_admin()));
    create policy "Shared delete history" on public.match_reschedule_history for delete to authenticated
      using (public.has_perm('edit') or public.has_perm('delete'));
  end if;
end $$;

-- v23: camera
alter table public.matches add column if not exists camera text not null default '';
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
