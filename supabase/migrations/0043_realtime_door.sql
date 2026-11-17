-- Live Door tab (2026-11-17, Cath: new door entries should appear without reloading the page).
-- camera_events joins the supabase_realtime publication, so the app's useDoorActivity hears inserts and updates
-- (a pass, its clip arriving, a name chosen on another phone) as they happen. RLS still applies: only household
-- members receive rows. Idempotent; no destructive statements.
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'camera_events') then
    alter publication supabase_realtime add table public.camera_events;
  end if;
end $$;
