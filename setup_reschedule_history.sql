-- Run in Supabase Dashboard -> SQL Editor after selecting your project.
-- Stores each date/time change separately, scoped to the signed-in user.
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
create policy "Users can view own reschedule history"
  on public.match_reschedule_history for select to authenticated
  using (auth.uid() = user_id);
drop policy if exists "Users can insert own reschedule history" on public.match_reschedule_history;
create policy "Users can insert own reschedule history"
  on public.match_reschedule_history for insert to authenticated
  with check (auth.uid() = user_id);
drop policy if exists "Users can delete own reschedule history" on public.match_reschedule_history;
create policy "Users can delete own reschedule history"
  on public.match_reschedule_history for delete to authenticated
  using (auth.uid() = user_id);
