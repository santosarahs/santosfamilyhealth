-- ============================================================
--  Santos Family Health Ledger — Supabase schema
--  Run this once in your project's SQL Editor (paste + Run).
--  Safe to re-run: it uses IF NOT EXISTS / OR REPLACE / DROP-and-create
--  for the policies.
-- ============================================================

create extension if not exists "pgcrypto";

-- ---------- tables ----------
create table if not exists public.members (
  id          uuid primary key default gen_random_uuid(),
  email       text not null unique,
  role        text not null default 'member' check (role in ('admin','member','viewer')),
  invited_by  uuid,
  created_at  timestamptz not null default now()
);
create index if not exists members_email_idx on public.members (lower(email));
-- roles: admin (everything) | member (view + add + edit) | viewer (view only)
alter table public.members drop constraint if exists members_role_check;
alter table public.members add  constraint members_role_check check (role in ('admin','member','viewer'));

create table if not exists public.people (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  relation    text,
  dob         date,
  sex         text,
  blood_type  text,
  allergies   jsonb not null default '[]'::jsonb,
  conditions  jsonb not null default '[]'::jsonb,
  care_team   jsonb not null default '[]'::jsonb,
  notes       text,
  created_by  uuid default auth.uid(),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists public.events (
  id          uuid primary key default gen_random_uuid(),
  person_id   uuid not null references public.people (id) on delete cascade,
  type        text not null,
  date        date not null default current_date,
  data        jsonb not null default '{}'::jsonb,
  attachments jsonb not null default '[]'::jsonb,
  created_by  uuid default auth.uid(),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists events_person_date_idx on public.events (person_id, date desc);

-- ---------- helper functions ----------
-- SECURITY DEFINER so they can read public.members without tripping
-- the members RLS policy (which itself calls is_member()).
create or replace function public.is_member() returns boolean
  language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.members
    where lower(email) = lower(coalesce(auth.jwt() ->> 'email',''))
  );
$$;

create or replace function public.is_admin() returns boolean
  language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.members
    where lower(email) = lower(coalesce(auth.jwt() ->> 'email',''))
      and role = 'admin'
  );
$$;

-- can this viewer change data? admins and members yes, viewers no.
create or replace function public.is_editor() returns boolean
  language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.members
    where lower(email) = lower(coalesce(auth.jwt() ->> 'email',''))
      and role in ('admin','member')
  );
$$;

revoke all on function public.is_member() from public;
revoke all on function public.is_admin()  from public;
revoke all on function public.is_editor() from public;
grant execute on function public.is_member() to authenticated;
grant execute on function public.is_admin()  to authenticated;
grant execute on function public.is_editor() to authenticated;

-- ---------- row level security ----------
alter table public.members enable row level security;
alter table public.people  enable row level security;
alter table public.events  enable row level security;

drop policy if exists members_select on public.members;
drop policy if exists members_insert on public.members;
drop policy if exists members_update on public.members;
drop policy if exists members_delete on public.members;
create policy members_select on public.members for select to authenticated using (public.is_member());
create policy members_insert on public.members for insert to authenticated with check (public.is_admin());
create policy members_update on public.members for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy members_delete on public.members for delete to authenticated using (public.is_admin());

drop policy if exists people_select on public.people;
drop policy if exists people_insert on public.people;
drop policy if exists people_update on public.people;
drop policy if exists people_delete on public.people;
create policy people_select on public.people for select to authenticated using (public.is_member());
create policy people_insert on public.people for insert to authenticated with check (public.is_editor());
create policy people_update on public.people for update to authenticated using (public.is_editor()) with check (public.is_editor());
create policy people_delete on public.people for delete to authenticated using (public.is_admin());  -- admin only

drop policy if exists events_select on public.events;
drop policy if exists events_insert on public.events;
drop policy if exists events_update on public.events;
drop policy if exists events_delete on public.events;
create policy events_select on public.events for select to authenticated using (public.is_member());
create policy events_insert on public.events for insert to authenticated with check (public.is_editor());
create policy events_update on public.events for update to authenticated using (public.is_editor()) with check (public.is_editor());
create policy events_delete on public.events for delete to authenticated using (public.is_admin());  -- admin only

-- ---------- storage bucket for attachments ----------
insert into storage.buckets (id, name, public)
values ('attachments','attachments', false)
on conflict (id) do nothing;

drop policy if exists attach_select on storage.objects;
drop policy if exists attach_insert on storage.objects;
drop policy if exists attach_update on storage.objects;
drop policy if exists attach_delete on storage.objects;
create policy attach_select on storage.objects for select to authenticated
  using (bucket_id = 'attachments' and public.is_member());
create policy attach_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'attachments' and public.is_editor());
create policy attach_update on storage.objects for update to authenticated
  using (bucket_id = 'attachments' and public.is_editor());
create policy attach_delete on storage.objects for delete to authenticated
  using (bucket_id = 'attachments' and public.is_editor());

-- ============================================================
--  AUDIT LOG  (safe to run on an existing project)
--  Records every insert / update / delete on people, events and
--  members - with the acting user's email taken from their token
--  server-side, so it can't be forged - plus one sign-in row per
--  session. Readable by admins only.
-- ============================================================
create table if not exists public.audit_log (
  id          bigint generated always as identity primary key,
  at          timestamptz not null default now(),
  actor_email text,
  actor_id    uuid,
  action      text not null,   -- insert | update | delete | signin | signout
  entity      text not null,   -- people | events | members | auth
  entity_id   uuid,
  person_id   uuid,
  summary     text
);
create index if not exists audit_log_at_idx on public.audit_log (at desc);

alter table public.audit_log enable row level security;
drop policy if exists audit_select on public.audit_log;
create policy audit_select on public.audit_log for select to authenticated using (public.is_admin());
-- no insert/update/delete policies: only the security-definer routines below write here.

create or replace function public.audit_change()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_actor   text;
  v_row     jsonb;
  v_id      uuid;
  v_person  uuid;
  v_summary text;
begin
  v_actor := lower(coalesce(auth.jwt() ->> 'email',''));
  if tg_op = 'DELETE' then v_row := to_jsonb(old); else v_row := to_jsonb(new); end if;
  v_id := nullif(v_row ->> 'id','')::uuid;

  if tg_table_name = 'events' then
    v_person  := nullif(v_row ->> 'person_id','')::uuid;
    v_summary := coalesce((select name from public.people where id = v_person), '?')
              || ' - ' || coalesce(v_row ->> 'type','')
              || ' - ' || left(coalesce(
                   v_row->'data'->>'purpose', v_row->'data'->>'panel',   v_row->'data'->>'drug',
                   v_row->'data'->>'reason',  v_row->'data'->>'chiefComplaint',
                   v_row->'data'->>'vaccine', v_row->'data'->>'title', ''), 80);
  elsif tg_table_name = 'people' then
    v_person  := v_id;
    v_summary := coalesce(v_row ->> 'name','?');
  elsif tg_table_name = 'members' then
    v_summary := coalesce(v_row ->> 'email','?') || ' (' || coalesce(v_row ->> 'role','') || ')';
  end if;

  insert into public.audit_log(actor_email, actor_id, action, entity, entity_id, person_id, summary)
  values (nullif(v_actor,''), auth.uid(), lower(tg_op), tg_table_name, v_id, v_person, v_summary);
  return null;
end $$;

drop trigger if exists audit_people  on public.people;
drop trigger if exists audit_events  on public.events;
drop trigger if exists audit_members on public.members;
create trigger audit_people  after insert or update or delete on public.people  for each row execute function public.audit_change();
create trigger audit_events  after insert or update or delete on public.events  for each row execute function public.audit_change();
create trigger audit_members after insert or update or delete on public.members for each row execute function public.audit_change();

create or replace function public.log_event(p_action text, p_summary text default '')
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_member() then return; end if;
  if p_action not in ('signin','signout') then return; end if;
  if p_action = 'signin' and exists (
        select 1 from public.audit_log
        where entity = 'auth' and action = 'signin'
          and actor_email = lower(coalesce(auth.jwt() ->> 'email',''))
          and at > now() - interval '30 minutes') then
    return;  -- collapse rapid reloads into one sign-in per 30 min
  end if;
  insert into public.audit_log(actor_email, actor_id, action, entity, summary)
  values (lower(coalesce(auth.jwt() ->> 'email','')), auth.uid(), p_action, 'auth', left(coalesce(p_summary,''),200));
end $$;

revoke all on function public.log_event(text, text) from public;
grant execute on function public.log_event(text, text) to authenticated;

-- make PostgREST pick up the new table/functions immediately
notify pgrst, 'reload schema';

-- ---------- OPTIONAL: instant multi-device updates ----------
-- Uncomment and run once to push live changes to open browsers.
-- The app also refreshes on window focus and after every save, so this
-- is a nice-to-have, not required.
-- alter publication supabase_realtime add table public.people;
-- alter publication supabase_realtime add table public.events;

-- ============================================================
--  FINAL STEP — make yourself the first admin.
--  Replace the email with the address you will SIGN IN with,
--  then run this line on its own:
-- ============================================================
-- insert into public.members (email, role) values ('you@example.com', 'admin');
