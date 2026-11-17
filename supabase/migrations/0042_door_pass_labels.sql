-- Door clips for every uncertain pass (2026-11-17, Cath: "always show the clip when you cannot id the person with at
-- least 95% certainty"). The Mac now sends wantClip for 'person' (a body, no face), 'unknown', and any name it is less
-- than 95 % sure of. A pass without a face snapshot is named as a whole:
--   label_door_pass(p_event_id, p_label)  household writers; relabels the event ('a' | 'b' | guest | 'forget').
--   camera_events.answered = the label chosen ('forget' keeps the event's label); retention then deletes the clip.
-- Idempotent; no destructive statements.

alter table public.camera_events add column if not exists answered text;
comment on column public.camera_events.answered is 'Door pass named as a whole in the app (label_door_pass): the label chosen, or forget.';

create or replace function private.label_door_pass(p_event_id bigint, p_label text)
returns public.camera_events
language plpgsql security definer set search_path = '' as $$
declare
  v_ev public.camera_events;
  v_label text := lower(btrim(coalesce(p_label, '')));
begin
  if not private.is_household_writer() then
    raise exception 'not allowed: owner or member role required' using errcode = '42501';
  end if;
  if v_label <> 'forget' and v_label !~ '^[a-z][a-z0-9_-]{0,39}$' then
    raise exception 'a name is lower-case letters, digits, - or _ (at most 40)' using errcode = '22023';
  end if;
  update public.camera_events e set
    label = case when v_label = 'forget' then e.label else v_label end,
    person_id = case when v_label in (select p.id from public.people p) then v_label when v_label = 'forget' then e.person_id else null end,
    confidence = case when v_label = 'forget' then e.confidence else 1 end,
    answered = v_label
  where e.id = p_event_id
  returning * into v_ev;
  if not found then raise exception 'no such door event' using errcode = '22023'; end if;
  return v_ev;
end $$;
revoke all on function private.label_door_pass(bigint, text) from public, anon;
grant execute on function private.label_door_pass(bigint, text) to authenticated;

create or replace function public.label_door_pass(p_event_id bigint, p_label text)
returns public.camera_events
language sql security invoker set search_path = '' as $$
  select * from private.label_door_pass(p_event_id, p_label)
$$;
revoke all on function public.label_door_pass(bigint, text) from public, anon;
grant execute on function public.label_door_pass(bigint, text) to authenticated;
