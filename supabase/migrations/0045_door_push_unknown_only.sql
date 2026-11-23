-- Door pushes only for new faces (2026-11-23): Cath asked that Jarvis stop notifying for faces it recognises.
--
-- private.entrance_notice (0039) now pushes only when the relay reports a face that matched nobody (label 'unknown'):
--   "New face at the front door (18:42)" · "Someone Jarvis hasn't seen before. Name them in the Door tab."
-- Recognised people (Cath, Erik, named guests such as the nanny) and passes with no face seen ('person') are no
-- longer pushed. They still appear in the Door timeline and in the 4-hourly summary.
-- At most one push per 10 minutes, as before. Idempotent; no destructive statements.

create or replace function private.entrance_notice() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_time text := to_char(new.ts at time zone 'Asia/Bangkok', 'HH24:MI');
begin
  if new.hidden or new.camera <> 'entrance' or new.label <> 'unknown' then return new; end if;
  if new.ts < now() - interval '15 minutes' then return new; end if; -- backfills stay silent
  if exists (select 1 from public.jarvis_notices n where n.kind = 'entrance:unknown' and n.sent_at > now() - interval '10 minutes') then
    return new;
  end if;
  perform private.jarvis_push('entrance:unknown', 'New face at the front door (' || v_time || ')',
    'Someone Jarvis hasn’t seen before. Name them in the Door tab.');
  return new;
exception when others then
  raise warning 'entrance_notice: %', sqlerrm;
  return new;
end $$;
revoke all on function private.entrance_notice() from public, anon, authenticated;
