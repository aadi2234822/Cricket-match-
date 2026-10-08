-- Agar database pehle se bana hai, sirf ye ek line Supabase SQL Editor me run karo:
alter table public.matches add column if not exists seq bigint generated always as identity;
