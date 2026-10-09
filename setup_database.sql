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
