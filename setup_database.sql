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
