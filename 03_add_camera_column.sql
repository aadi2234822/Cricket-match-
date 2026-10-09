-- Run once in Supabase Dashboard -> SQL Editor (safe to run repeatedly).
-- v23: which camera each match is recorded on
alter table public.matches add column if not exists camera text not null default '';

-- Lets users who only have "Status & checklist" permission also set the camera
-- (needed only if you already ran add_roles.sql; harmless otherwise)
create or replace function public.matches_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare keep text[] := array['status','recorded','uploaded','checklist','video_link','recording_remarks','camera'];
begin
  if auth.uid() is null then return new; end if;
  if public.has_perm('edit') then return new; end if;
  if public.has_perm('status') then
    if (to_jsonb(new) - keep) is distinct from (to_jsonb(old) - keep) then
      raise exception 'You may only change status, checklist, link, camera and remarks.';
    end if;
    return new;
  end if;
  raise exception 'You do not have permission to edit matches.';
end; $$;
