-- ===========================================================================
-- Social Capital Ireland — database setup
-- ===========================================================================
-- HOW TO RUN THIS
--   1. Go to your Supabase dashboard
--   2. Left sidebar -> SQL Editor -> "New query"
--   3. Paste this entire file in
--   4. Press "Run"
-- It is safe to run more than once.
-- ===========================================================================

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- Fixed lists of allowed values.
-- These show up as dropdowns in the Supabase table editor, which makes typing
-- entries in by hand much harder to get wrong.
--
-- To add an industry later, run:  alter type industry_slug add value 'sport';
-- ---------------------------------------------------------------------------
do $$ begin
  create type industry_slug as enum (
    'technology','healthcare','law','finance','trades',
    'media','education','engineering','public_sector','other'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type mentor_level as enum ('junior','senior');
exception when duplicate_object then null; end $$;


-- ---------------------------------------------------------------------------
-- 1. schools — the approved list. THIS TABLE IS THE ACCESS GATE.
--    An email in here (with is_active = true) can see the mentor directory.
--    An email not in here sees nothing, even if they manage to log in.
-- ---------------------------------------------------------------------------
create table if not exists public.schools (
  id            uuid primary key default gen_random_uuid(),
  created_at    timestamptz not null default now(),
  school_name   text not null,
  contact_name  text,
  email         text not null,
  county        text,
  roll_number   text,            -- the school's DEIS roll number, if you want it
  is_active     boolean not null default true
);

-- Email matching ignores capitals, so Mary@School.ie and mary@school.ie
-- are treated as the same login.
create unique index if not exists schools_email_lower_idx
  on public.schools (lower(email));


-- ---------------------------------------------------------------------------
-- 2. mentors — the directory. Only non-sensitive, displayable fields.
--    Deliberately contains NO email or phone number: see mentor_contacts.
-- ---------------------------------------------------------------------------
create table if not exists public.mentors (
  id               uuid primary key default gen_random_uuid(),
  created_at       timestamptz not null default now(),
  full_name        text not null,
  role_title       text not null,          -- "Software Engineer, Google Dublin"
  industry         industry_slug not null,
  level            mentor_level not null,  -- junior or senior
  experience_label text,                   -- "3 years in industry"
  open_to_talks    boolean not null default false,
  is_published     boolean not null default true  -- untick to hide without deleting
);

create index if not exists mentors_industry_idx
  on public.mentors (industry) where is_published;


-- ---------------------------------------------------------------------------
-- 3. mentor_contacts — private contact details.
--    NOTHING on the website can read this table, not even a logged-in school.
--    You see it only here in the dashboard. You make the introductions.
-- ---------------------------------------------------------------------------
create table if not exists public.mentor_contacts (
  mentor_id   uuid primary key references public.mentors(id) on delete cascade,
  created_at  timestamptz not null default now(),
  email       text not null,
  phone       text,
  company     text,
  notes       text
);


-- ---------------------------------------------------------------------------
-- 4. pending_schools — registration submissions waiting for your approval.
--    The public can add rows. Nobody can read them back through the website.
-- ---------------------------------------------------------------------------
create table if not exists public.pending_schools (
  id           uuid primary key default gen_random_uuid(),
  created_at   timestamptz not null default now(),
  school_name  text not null check (char_length(school_name) between 2 and 200),
  contact_name text not null check (char_length(contact_name) between 2 and 120),
  email        text not null check (char_length(email) between 5 and 200),
  county       text          check (county is null or char_length(county) <= 60),
  status       text not null default 'pending'
                 check (status in ('pending','approved','rejected'))
);


-- ---------------------------------------------------------------------------
-- 5. pending_mentors — mentor signups awaiting approval.
--    Fed by BOTH the mentors.html form and the businesses.html modal;
--    the `source` column tells you which.
-- ---------------------------------------------------------------------------
create table if not exists public.pending_mentors (
  id               uuid primary key default gen_random_uuid(),
  created_at       timestamptz not null default now(),
  full_name        text not null check (char_length(full_name) between 2 and 160),
  email            text not null check (char_length(email) between 5 and 200),
  company          text          check (company is null or char_length(company) <= 200),
  industry         industry_slug,
  experience_level text,   -- free text from the form: "Junior (0-5 years)" etc.
  open_to_talks    text,   -- free text from the form: "Yes, happy to" etc.
  source           text not null check (source in ('mentors_page','business_modal')),
  status           text not null default 'pending'
                     check (status in ('pending','approved','rejected'))
);


-- ===========================================================================
-- THE ACCESS GATE
-- ===========================================================================
-- This function answers one question: "is the person currently logged in
-- using an email that belongs to an approved, active school?"
--
-- It is `security definer`, which means it is allowed to look inside the
-- schools table even though the person calling it is not. That is the whole
-- point: it can answer yes/no without ever handing over the list of schools.
-- ---------------------------------------------------------------------------
create or replace function public.is_approved_school()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.schools
    where lower(email) = lower(auth.jwt() ->> 'email')
      and is_active
  );
$$;

revoke all on function public.is_approved_school() from public;
grant execute on function public.is_approved_school() to authenticated;


-- ===========================================================================
-- ROW LEVEL SECURITY
-- ===========================================================================
-- Rule of thumb for reading what follows:
--   "enable row level security" = deny everything by default.
--   Each "create policy" then punches one specific, narrow hole.
--   A table with RLS on and NO select policy cannot be read by anyone
--   through the website, full stop.
-- ---------------------------------------------------------------------------

alter table public.schools          enable row level security;
alter table public.mentors          enable row level security;
alter table public.mentor_contacts  enable row level security;
alter table public.pending_schools  enable row level security;
alter table public.pending_mentors  enable row level security;

-- Clear out old versions so this file can be re-run safely.
drop policy if exists "submit school registration"      on public.pending_schools;
drop policy if exists "submit mentor signup"            on public.pending_mentors;
drop policy if exists "school reads its own record"     on public.schools;
drop policy if exists "approved schools read mentors"   on public.mentors;

-- Anyone visiting the site may SUBMIT a registration...
create policy "submit school registration"
  on public.pending_schools for insert
  to anon, authenticated
  with check (true);

-- ...and a mentor signup. Note: insert only. There is no select policy on
-- either pending table, so nobody can read the submissions back.
create policy "submit mentor signup"
  on public.pending_mentors for insert
  to anon, authenticated
  with check (true);

-- A logged-in school may read its OWN row only (so the site can greet them
-- by their school's name). It cannot see any other school.
create policy "school reads its own record"
  on public.schools for select
  to authenticated
  using (lower(email) = lower(auth.jwt() ->> 'email'));

-- THE MAIN GATE: published mentors are readable only by a logged-in user
-- whose email is on the approved schools list.
create policy "approved schools read mentors"
  on public.mentors for select
  to authenticated
  using (is_published and public.is_approved_school());

-- mentor_contacts gets NO policy at all, on purpose. Belt and braces:
revoke all on public.mentor_contacts from anon, authenticated;


-- ===========================================================================
-- APPROVAL HELPERS
-- ===========================================================================
-- Run these in the SQL Editor to approve a submission without retyping it.
-- They only work here in the dashboard, not from the website.
--
--   select public.approve_school('paste-the-id-here');
--
--   select public.approve_mentor(
--     'paste-the-id-here',
--     'Software Engineer, Google Dublin',  -- job title as it should appear
--     'junior',                            -- 'junior' or 'senior'
--     '3 years in industry'                -- the small grey text on the card
--   );
-- ---------------------------------------------------------------------------

create or replace function public.approve_school(pending_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  p public.pending_schools%rowtype;
  new_id uuid;
begin
  select * into p from public.pending_schools where id = pending_id;
  if not found then
    raise exception 'No pending school with id %', pending_id;
  end if;

  insert into public.schools (school_name, contact_name, email, county)
  values (p.school_name, p.contact_name, lower(p.email), p.county)
  on conflict (lower(email)) do update
    set is_active = true, school_name = excluded.school_name
  returning id into new_id;

  update public.pending_schools set status = 'approved' where id = pending_id;
  return new_id;
end;
$$;

create or replace function public.approve_mentor(
  pending_id       uuid,
  role_title       text,
  level            mentor_level,
  experience_label text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  p public.pending_mentors%rowtype;
  new_id uuid;
begin
  select * into p from public.pending_mentors where id = pending_id;
  if not found then
    raise exception 'No pending mentor with id %', pending_id;
  end if;

  insert into public.mentors
    (full_name, role_title, industry, level, experience_label, open_to_talks)
  values
    (p.full_name, role_title, coalesce(p.industry, 'other'), level,
     experience_label, coalesce(p.open_to_talks ilike 'yes%', false))
  returning id into new_id;

  insert into public.mentor_contacts (mentor_id, email, company)
  values (new_id, lower(p.email), p.company);

  update public.pending_mentors set status = 'approved' where id = pending_id;
  return new_id;
end;
$$;

revoke all on function public.approve_school(uuid) from public, anon, authenticated;
revoke all on function public.approve_mentor(uuid, text, mentor_level, text)
  from public, anon, authenticated;
