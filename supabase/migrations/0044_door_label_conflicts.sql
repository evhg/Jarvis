-- Naming a door pass when the same name already has a row at that instant (2026-11-17: "duplicate key value violates
-- unique constraint camera_events_camera_ts_label_key" when Cath labelled a pass Erik). (camera, ts, label) is unique,
-- so a pass that would collide is merged instead: it keeps its label, takes the person_id, is answered and hidden
-- (the existing row already shows that person at that moment). Same rule in name_door_face for a one-person pass.
-- Idempotent; no destructive statements.

create or replace function private.label_door_pass(p_event_id bigint, p_label text)
returns public.camera_events
language plpgsql security definer set search_path = '' as $$
declare
  v_ev public.camera_events;
  v_label text := lower(btrim(coalesce(p_label, '')));
  v_clash boolean;
  v_pid text;
begin
  if not private.is_household_writer() then
    raise exception 'not allowed: owner or member role required' using errcode = '42501';
  end if;
  if v_label <> 'forget' and v_label !~ '^[a-z][a-z0-9_-]{0,39}$' then
    raise exception 'a name is lower-case letters, digits, - or _ (at most 40)' using errcode = '22023';
  end if;
  select * into v_ev from public.camera_events e where e.id = p_event_id for update;
  if not found then raise exception 'no such door event' using errcode = '22023'; end if;
  v_pid := case when v_label in (select p.id from public.people p) then v_label end;
  v_clash := v_label <> 'forget' and v_label <> v_ev.label and exists (
    select 1 from public.camera_events c where c.camera = v_ev.camera and c.ts = v_ev.ts and c.label = v_label and c.id <> v_ev.id);
  update public.camera_events e set
    label = case when v_label = 'forget' or v_clash then e.label else v_label end,
    person_id = case when v_label = 'forget' then e.person_id else v_pid end,
    confidence = case when v_label = 'forget' then e.confidence else 1 end,
    hidden = e.hidden or v_clash,
    answered = v_label
  where e.id = p_event_id
  returning * into v_ev;
  return v_ev;
end $$;
revoke all on function private.label_door_pass(bigint, text) from public, anon;
grant execute on function private.label_door_pass(bigint, text) to authenticated;

create or replace function private.name_door_face(p_event_id bigint, p_person integer, p_label text)
returns public.camera_events
language plpgsql security definer set search_path = '' as $$
declare
  v_ev public.camera_events;
  v_label text := lower(btrim(coalesce(p_label, '')));
  v_faces text[];
  v_people jsonb;
  v_one boolean;
  v_clash boolean;
begin
  if not private.is_household_writer() then
    raise exception 'not allowed: owner or member role required' using errcode = '42501';
  end if;
  if v_label <> 'forget' and v_label !~ '^[a-z][a-z0-9_-]{0,39}$' then
    raise exception 'a name is lower-case letters, digits, - or _ (at most 40)' using errcode = '22023';
  end if;
  select * into v_ev from public.camera_events e where e.id = p_event_id for update;
  if not found then raise exception 'no such door event' using errcode = '22023'; end if;
  v_people := coalesce(v_ev.people, '[]'::jsonb);
  if p_person < 0 or p_person >= jsonb_array_length(v_people) then
    raise exception 'no such person in this pass' using errcode = '22023';
  end if;
  select coalesce(array_agg(f), '{}') into v_faces from jsonb_array_elements_text(v_people -> p_person -> 'faces') f;
  insert into public.face_names (event_id, person_index, faces, label, chosen_by)
  values (p_event_id, p_person, v_faces, v_label, (select auth.uid()));
  v_people := jsonb_set(v_people, array[p_person::text, 'label'], to_jsonb(v_label));
  v_one := jsonb_array_length(v_people) = 1 and v_label <> 'forget';
  v_clash := v_one and v_label <> v_ev.label and exists (
    select 1 from public.camera_events c where c.camera = v_ev.camera and c.ts = v_ev.ts and c.label = v_label and c.id <> v_ev.id);
  update public.camera_events e set
    people = v_people,
    label = case when v_one and not v_clash then v_label else e.label end,
    person_id = case when v_one and v_label in (select p.id from public.people p) then v_label else e.person_id end,
    hidden = e.hidden or v_clash
  where e.id = p_event_id
  returning * into v_ev;
  return v_ev;
end $$;
revoke all on function private.name_door_face(bigint, integer, text) from public, anon;
grant execute on function private.name_door_face(bigint, integer, text) to authenticated;
