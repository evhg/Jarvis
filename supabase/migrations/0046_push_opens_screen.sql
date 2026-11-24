-- Pushes open the screen they are about (2026-11-24): a tap on a Jarvis notification used to open Today.
--
-- private.jarvis_push now passes push-admin a path and a tag from the notice kind:
--   entrance:*      → /live      the Door tab (clip, "Who was it?")
--   bedtime:*       → /room      the room (Fitbit, CO₂, the listener)
--   weekly_health*  → /body      health trends
--   anything else   → /          Today (presence, the morning brief…)
-- The tag is the kind's prefix, so a door notice no longer replaces the bedtime one on the lock screen.
-- Idempotent; no destructive statements.

create or replace function private.jarvis_push(p_kind text, p_title text, p_body text)
returns bigint
language plpgsql security definer set search_path = '' as $$
declare
  v_req bigint;
  v_prefix text := split_part(coalesce(p_kind, ''), ':', 1);
  v_path text := case
    when v_prefix = 'entrance' then '/live'
    when v_prefix = 'bedtime' then '/room'
    when v_prefix like 'weekly_health%' then '/body'
    else '/'
  end;
begin
  v_req := private.invoke_edge_function('push-admin', jsonb_build_object('action', 'test', 'title', left(p_title, 80),
    'body', left(p_body, 200), 'path', v_path, 'tag', coalesce(nullif(v_prefix, ''), 'jarvis')), 15000);
  insert into public.jarvis_notices (kind, title, body, request_id) values (p_kind, p_title, p_body, v_req);
  return v_req;
end $$;
revoke all on function private.jarvis_push(text, text, text) from public, anon, authenticated;
