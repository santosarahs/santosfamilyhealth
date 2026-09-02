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
  role        text not null default 'member' check (role in ('admin','member')),
  invited_by  uuid,
  created_at  timestamptz not null default now()
);
create index if not exists members_email_idx on public.members (lower(email));

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

revoke all on function public.is_member() from public;
revoke all on function public.is_admin() from public;
grant execute on function public.is_member() to authenticated;
grant execute on function public.is_admin() to authenticated;

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
create policy people_insert on public.people for insert to authenticated with check (public.is_member());
create policy people_update on public.people for update to authenticated using (public.is_member()) with check (public.is_member());
create policy people_delete on public.people for delete to authenticated using (public.is_member());

drop policy if exists events_select on public.events;
drop policy if exists events_insert on public.events;
drop policy if exists events_update on public.events;
drop policy if exists events_delete on public.events;
create policy events_select on public.events for select to authenticated using (public.is_member());
create policy events_insert on public.events for insert to authenticated with check (public.is_member());
create policy events_update on public.events for update to authenticated using (public.is_member()) with check (public.is_member());
create policy events_delete on public.events for delete to authenticated using (public.is_member());

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
  with check (bucket_id = 'attachments' and public.is_member());
create policy attach_update on storage.objects for update to authenticated
  using (bucket_id = 'attachments' and public.is_member());
create policy attach_delete on storage.objects for delete to authenticated
  using (bucket_id = 'attachments' and public.is_member());

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
