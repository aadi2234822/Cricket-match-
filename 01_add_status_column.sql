-- Run once in Supabase Dashboard -> SQL Editor (safe to run repeatedly).
-- Adds the status workflow: Scheduled > Recording > Recorded > Editing > Uploaded (+ Postponed / Abandoned / Cancelled)
alter table public.matches add column if not exists status text not null default 'Scheduled';
alter table public.matches drop constraint if exists matches_status_check;
alter table public.matches add constraint matches_status_check
  check (status in ('Scheduled','Recording','Recorded','Editing','Uploaded','Postponed','Abandoned','Cancelled'));
-- Backfill existing rows from the old Recorded / Uploaded fields
update public.matches
set status = case when uploaded = 'Done' then 'Uploaded' when recorded = 'Done' then 'Recorded' else 'Scheduled' end
where status = 'Scheduled';
