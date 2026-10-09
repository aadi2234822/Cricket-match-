-- ============================================================
-- v22: Admin / User roles with admin-granted permissions
-- Run ONCE in Supabase Dashboard -> SQL Editor (safe to run again).
-- Run add_status_column.sql and add_v21_columns.sql first.
-- ============================================================

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
