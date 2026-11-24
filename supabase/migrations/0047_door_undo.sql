-- Undo a door name (2026-11-24): Cath asked for an undo button after a misclick.
--
-- undo_door_name(p_event_id, p_person)
--   p_person >= 0: clears people[p_person].label, so the snapshot asks "Who was it?" again. A face_names row with
--                  label 'forget' tells the Mac to drop the samples it learned from those face ids. When the pass had
--                  a single person, its label/person_id go back to 'unknown'.
--   p_person = -1: a pass named as a whole (label_door_pass): clears answered; label goes back to 'person'.
-- Snapshots and clips are now kept 14 days even when named (camera-event v5), so the face can be looked at again.
-- Idempotent; no destructive statements.

create or replace function private.undo_door_name(p_event_id bigint, p_person integer)
returns public.camera_events
language plpgsql security definer set search_path = '' as $$
declare
  v_ev public.camera_events;
  v_people jsonb;
  v_faces text[];
begin
  if not private.is_household_writer() then
    raise exception 'not allowed: owner or member role required' using errcode = '42501';
  end if;
  select * into v_ev from public.camera_events e where e.id = p_event_id for update;
  if not found then raise exception 'no such door event' using errcode = '22023'; end if;
  if p_person < 0 then
    update public.camera_events e set answered = null,
      label = case when exists (select 1 from public.camera_events c where c.camera = e.camera and c.ts = e.ts and c.label = 'person' and c.id <> e.id)
                   then e.label else 'person' end,
      person_id = null, confidence = null
    where e.id = p_event_id returning * into v_ev;
    return v_ev;
  end if;
  v_people := coalesce(v_ev.people, '[]'::jsonb);
  if p_person >= jsonb_array_length(v_people) then raise exception 'no such person in this pass' using errcode = '22023'; end if;
  select coalesce(array_agg(f), '{}') into v_faces from jsonb_array_elements_text(v_people -> p_person -> 'faces') f;
  if cardinality(v_faces) > 0 then
    insert into public.face_names (event_id, person_index, faces, label, chosen_by)
    values (p_event_id, p_person, v_faces, 'forget', (select auth.uid()));
  end if;
  v_people := jsonb_set(v_people, array[p_person::text, 'label'], 'null'::jsonb);
  update public.camera_events e set
    people = v_people,
    label = case when jsonb_array_length(v_people) = 1
                  and not exists (select 1 from public.camera_events c where c.camera = e.camera and c.ts = e.ts and c.label = 'unknown' and c.id <> e.id)
                 then 'unknown' else e.label end,
    person_id = case when jsonb_array_length(v_people) = 1 then null else e.person_id end
  where e.id = p_event_id
  returning * into v_ev;
  return v_ev;
end $$;
revoke all on function private.undo_door_name(bigint, integer) from public, anon;
grant execute on function private.undo_door_name(bigint, integer) to authenticated;

create or replace function public.undo_door_name(p_event_id bigint, p_person integer)
returns public.camera_events
language sql security invoker set search_path = '' as $$
  select * from private.undo_door_name(p_event_id, p_person)
$$;
revoke all on function public.undo_door_name(bigint, integer) from public, anon;
grant execute on function public.undo_door_name(bigint, integer) to authenticated;
