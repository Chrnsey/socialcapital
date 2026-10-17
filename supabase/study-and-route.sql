-- ===========================================================================
-- HOW SOMEBODY GOT THERE, NOT JUST WHAT THEY DO NOW
-- ===========================================================================
-- A job title tells a student what a person does. It does not tell them
-- whether that person went straight to college, did a PLC first, served an
-- apprenticeship, or left school at eighteen and worked their way up. For a
-- fifteen-year-old deciding what to do next, the second thing is worth more.
--
-- Four new fields, all optional. A mentor who left school after the Leaving
-- Cert has nothing to put in "field of study" and that is fine - it is not a
-- gap in their record.
--
-- Run this once, AFTER admin-page.sql and admin-pending.sql.
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- 1. The lists.
--
-- These are TEXT with a check constraint, not enums like industry_slug. That
-- is deliberate and it breaks with the pattern elsewhere in this schema:
-- these two lists are editorial judgements about how people are described and
-- they will be revised. A check constraint can be dropped and rewritten in
-- two statements. A Postgres enum can have values added but not removed or
-- renamed without rebuilding the column.
--
-- To change a list later, see the bottom of this file.
-- ---------------------------------------------------------------------------
alter table public.mentors
  add column if not exists route_in     text,
  add column if not exists study_field  text,
  add column if not exists study_detail text,   -- free text: "General Nursing, DCU"
  add column if not exists qualification text;

alter table public.mentors drop constraint if exists mentors_route_in_check;
alter table public.mentors add constraint mentors_route_in_check
  check (route_in is null or route_in in (
    'college',            -- Leaving Cert straight into higher education
    'plc_then_college',   -- PLC or QQI first, then on
    'apprenticeship',
    'traineeship',
    'work_from_school',   -- straight into work, trained on the job
    'mature_student',     -- went back later
    'abroad',             -- studied outside Ireland
    'other'
  ));

alter table public.mentors drop constraint if exists mentors_study_field_check;
alter table public.mentors add constraint mentors_study_field_check
  check (study_field is null or study_field in (
    'business', 'law', 'engineering', 'computing', 'science',
    'health_care', 'education', 'arts_humanities', 'social_science',
    'construction_property', 'trades_craft', 'media_design',
    'agriculture_environment', 'hospitality_tourism', 'sport_fitness',
    'other'
  ));

alter table public.mentors drop constraint if exists mentors_qualification_check;
alter table public.mentors add constraint mentors_qualification_check
  check (qualification is null or qualification in (
    'leaving_cert',
    'apprenticeship',
    'plc_qqi',
    'degree',
    'postgrad',
    'other'
  ));

comment on column public.mentors.route_in is
  'How they got into the work. The most useful field on the card for a
   student choosing what to do after school.';
comment on column public.mentors.study_field is
  'Broad area, so the directory can filter on it. Null is normal.';


-- ---------------------------------------------------------------------------
-- 2. Let signed-in schools read them.
--
-- EASY TO MISS. The grant on this table is column-by-column: select was
-- revoked wholesale and then granted on a named list, so that public_contact
-- stays unreadable. A new column is not in that list, which means a school
-- would get nulls back and nobody would know why. Re-grant.
-- ---------------------------------------------------------------------------
grant select (route_in, study_field, study_detail, qualification)
  on public.mentors to authenticated;


-- ---------------------------------------------------------------------------
-- 3. Remove the OLD versions of the functions first.
--
-- THIS IS THE BIT THAT CAUGHT ME OUT. "create or replace function" only
-- replaces when the argument list matches EXACTLY. These functions gain four
-- parameters, so a plain create-or-replace leaves the old version in place
-- and adds a second one beside it. Postgres then refuses to grant, revoke or
-- call either, because the name is no longer unique:
--
--   ERROR: function name "public.add_mentor" is not unique
--
-- Dropping them by oid rather than by a hand-written argument list means
-- every version goes, however many there are and whatever they look like.
-- ---------------------------------------------------------------------------
do $$
declare
  f record;
begin
  for f in
    select p.oid::regprocedure as signature
      from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.proname in ('add_mentor', 'admin_add_mentor',
                         'admin_update_mentor', 'admin_list_mentors')
  loop
    execute 'drop function ' || f.signature;
  end loop;
end $$;


-- ---------------------------------------------------------------------------
-- 4. Create them again, with the new fields.
-- ---------------------------------------------------------------------------
create or replace function public.add_mentor(
  full_name            text,
  role_title           text,
  industry             industry_slug,
  level                mentor_level,
  contact_email        text,
  experience_label     text    default null,
  open_to_talks        boolean default false,
  is_alumnus           boolean default false,
  alumnus_school_name  text    default null,
  alumni_contact_ok    boolean default false,
  public_contact       text    default null,
  public_contact_kind  text    default null,
  employer             text    default null,
  phone                text    default null,
  notes                text    default null,
  publish              boolean default false,
  route_in             text    default null,
  study_field          text    default null,
  study_detail         text    default null,
  qualification        text    default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id uuid;
begin
  insert into public.mentors (
    full_name, role_title, industry, level, experience_label,
    open_to_talks, is_alumnus, alumnus_school_name, alumni_contact_ok,
    public_contact, public_contact_kind, is_published,
    route_in, study_field, study_detail, qualification
  )
  values (
    add_mentor.full_name, add_mentor.role_title, add_mentor.industry,
    add_mentor.level, add_mentor.experience_label, add_mentor.open_to_talks,
    add_mentor.is_alumnus, add_mentor.alumnus_school_name,
    add_mentor.alumni_contact_ok, add_mentor.public_contact,
    add_mentor.public_contact_kind, add_mentor.publish,
    add_mentor.route_in, add_mentor.study_field,
    add_mentor.study_detail, add_mentor.qualification
  )
  returning id into new_id;

  insert into public.mentor_contacts (mentor_id, email, phone, company, notes)
  values (new_id, add_mentor.contact_email, add_mentor.phone,
          add_mentor.employer, add_mentor.notes);

  return new_id;
end;
$$;

revoke execute on function public.add_mentor from public, anon, authenticated;


create or replace function public.admin_add_mentor(
  p_full_name            text,
  p_role_title           text,
  p_industry             industry_slug,
  p_level                mentor_level,
  p_contact_email        text,
  p_experience_label     text    default null,
  p_open_to_talks        boolean default false,
  p_is_alumnus           boolean default false,
  p_alumnus_school_name  text    default null,
  p_alumni_contact_ok    boolean default false,
  p_public_contact       text    default null,
  p_public_contact_kind  text    default null,
  p_employer             text    default null,
  p_phone                text    default null,
  p_notes                text    default null,
  p_route_in             text    default null,
  p_study_field          text    default null,
  p_study_detail         text    default null,
  p_qualification        text    default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Not permitted' using errcode = '42501';
  end if;
  if coalesce(trim(p_full_name), '') = '' then
    raise exception 'A name is required' using errcode = '22023';
  end if;
  if coalesce(trim(p_contact_email), '') = '' then
    raise exception 'A contact email is required' using errcode = '22023';
  end if;

  return public.add_mentor(
    full_name           => trim(p_full_name),
    role_title          => trim(p_role_title),
    industry            => p_industry,
    level               => p_level,
    contact_email       => lower(trim(p_contact_email)),
    experience_label    => nullif(trim(coalesce(p_experience_label, '')), ''),
    open_to_talks       => p_open_to_talks,
    is_alumnus          => p_is_alumnus,
    alumnus_school_name => nullif(trim(coalesce(p_alumnus_school_name, '')), ''),
    alumni_contact_ok   => p_alumni_contact_ok,
    public_contact      => nullif(trim(coalesce(p_public_contact, '')), ''),
    public_contact_kind => nullif(trim(coalesce(p_public_contact_kind, '')), ''),
    employer            => nullif(trim(coalesce(p_employer, '')), ''),
    phone               => nullif(trim(coalesce(p_phone, '')), ''),
    notes               => nullif(trim(coalesce(p_notes, '')), ''),
    publish             => false,
    route_in            => nullif(trim(coalesce(p_route_in, '')), ''),
    study_field         => nullif(trim(coalesce(p_study_field, '')), ''),
    study_detail        => nullif(trim(coalesce(p_study_detail, '')), ''),
    qualification       => nullif(trim(coalesce(p_qualification, '')), '')
  );
end;
$$;

revoke all on function public.admin_add_mentor from public, anon;
grant execute on function public.admin_add_mentor to authenticated;


create or replace function public.admin_update_mentor(
  p_mentor_id            uuid,
  p_full_name            text,
  p_role_title           text,
  p_industry             industry_slug,
  p_level                mentor_level,
  p_experience_label     text    default null,
  p_open_to_talks        boolean default false,
  p_is_alumnus           boolean default false,
  p_alumnus_school_name  text    default null,
  p_alumni_contact_ok    boolean default false,
  p_public_contact       text    default null,
  p_public_contact_kind  text    default null,
  p_route_in             text    default null,
  p_study_field          text    default null,
  p_study_detail         text    default null,
  p_qualification        text    default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Not permitted' using errcode = '42501';
  end if;

  update public.mentors
     set full_name           = trim(p_full_name),
         role_title          = trim(p_role_title),
         industry            = p_industry,
         level               = p_level,
         experience_label    = nullif(trim(coalesce(p_experience_label, '')), ''),
         open_to_talks       = p_open_to_talks,
         is_alumnus          = p_is_alumnus,
         alumnus_school_name = nullif(trim(coalesce(p_alumnus_school_name, '')), ''),
         alumni_contact_ok   = p_alumni_contact_ok,
         public_contact      = nullif(trim(coalesce(p_public_contact, '')), ''),
         public_contact_kind = nullif(trim(coalesce(p_public_contact_kind, '')), ''),
         route_in            = nullif(trim(coalesce(p_route_in, '')), ''),
         study_field         = nullif(trim(coalesce(p_study_field, '')), ''),
         study_detail        = nullif(trim(coalesce(p_study_detail, '')), ''),
         qualification       = nullif(trim(coalesce(p_qualification, '')), '')
   where id = p_mentor_id;

  return found;
end;
$$;

revoke all on function public.admin_update_mentor from public, anon;
grant execute on function public.admin_update_mentor to authenticated;


-- ---------------------------------------------------------------------------
-- 5. Show the new fields on the admin list.
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_mentors()
returns table (
  id                  uuid,
  full_name           text,
  role_title          text,
  industry            industry_slug,
  level               mentor_level,
  experience_label    text,
  open_to_talks       boolean,
  is_alumnus          boolean,
  alumnus_school_name text,
  alumni_contact_ok   boolean,
  public_contact      text,
  is_published        boolean,
  contact_email       text,
  employer            text,
  notes               text,
  created_at          timestamptz,
  route_in            text,
  study_field         text,
  study_detail        text,
  qualification       text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Not permitted' using errcode = '42501';
  end if;

  return query
    select m.id, m.full_name, m.role_title, m.industry, m.level,
           m.experience_label, m.open_to_talks, m.is_alumnus,
           m.alumnus_school_name, m.alumni_contact_ok, m.public_contact,
           m.is_published, c.email, c.company, c.notes, m.created_at,
           m.route_in, m.study_field, m.study_detail, m.qualification
      from public.mentors m
      left join public.mentor_contacts c on c.mentor_id = m.id
     order by m.is_published, m.created_at desc;
end;
$$;

revoke all on function public.admin_list_mentors from public, anon;
grant execute on function public.admin_list_mentors to authenticated;


-- ===========================================================================
-- CHANGING A LIST LATER
-- ===========================================================================
-- Two statements. Add or remove values in the second one, and make sure no
-- existing row uses a value you are dropping:
--
--   select distinct route_in from public.mentors;
--   alter table public.mentors drop constraint mentors_route_in_check;
--   alter table public.mentors add constraint mentors_route_in_check
--     check (route_in is null or route_in in ('college', 'your_new_value'));
--
-- The admin page's dropdowns are in js/admin-mentors.js. The two lists have
-- to match, or saving fails with a constraint violation.
-- ===========================================================================
