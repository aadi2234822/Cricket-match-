-- Run once in Supabase Dashboard -> SQL Editor (safe to run repeatedly).
-- v21: upload link + per-match checklist
alter table public.matches add column if not exists video_link text not null default '';
alter table public.matches add column if not exists checklist jsonb not null default '{}'::jsonb;
