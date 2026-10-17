-- ===========================================================================
-- A FEW LINES IN THE MENTOR'S OWN WORDS
-- ===========================================================================
-- A student's problem is not finding somebody with a relevant job title. It
-- is working up the nerve to ask them anything. Knowing that somebody plays
-- camogie, or was the first in their family to go to college, does more for
-- that than any sector tag.
--
-- Rules this field is built around:
--
--   It is THEIR words. Not a description written about them. Paste what they
--   send you. If they will not write one, leave it empty - an empty bio is
--   better than one you invented, and the site has a standing rule against
--   putting words in a real person's mouth.
--
--   It is SHORT. 500 characters, enforced below. Three sentences. A long bio
--   buries everybody else in the sector.
--
--   It CANNOT CARRY CONTACT DETAILS. To be accurate about why, because it is
--   not that students log in - they do not. The directory is read by school
--   staff and by alumni over 18, and nobody under 18 has an account.
--
--   The route to a student is indirect and needs no login: a guidance
--   counsellor shows the directory on screen, or prints a few profiles. A
--   bio reading "find me on Instagram @whoever" is then copied down by a
--   fifteen-year-old who messages that person directly, which is exactly the
--   bypass the safeguarding statement exists to prevent. It also stops
--   mattering in theory the day students get their own logins, which is
--   already the intention.
--
--   The admin page warns about handles, links and phone-shaped numbers. You
--   are the check; the warning only makes sure you look.
--
-- Run after study-and-route.sql.
-- ===========================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. The column.
-- ---------------------------------------------------------------------------
alter table public.mentors
  add column if not exists bio text;

alter table public.mentors drop constraint if exists mentors_bio_length_check;
alter table public.mentors add constraint mentors_bio_length_check
  check (bio is null or char_length(bio) <= 500);

comment on column public.mentors.bio is
  'Up to 500 characters in the mentor''s OWN words. Never written on their
   behalf. Must not contain contact details - contact goes through the
   school - see the Child Safeguarding Statement. Read by school staff and
   by alumni over 18; students have no login, but staff show them the
   screen.';


-- ---------------------------------------------------------------------------
-- 2. Let signed-in schools read it.
--    Same trap as last time: select on this table is granted column by
--    column, so a new column is unreadable until it is named here.
-- ---------------------------------------------------------------------------
grant select (bio) on public.mentors to authenticated;


-- ---------------------------------------------------------------------------
-- 3. Drop the old versions before recreating.
--    Learned the hard way: create-or-replace with a longer argument list adds
--    a second function rather than replacing the first, and then nothing can
--    refer to either by name. Dropping by oid catches every version.
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
-- 4. Recreate, with bio on the end.
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
  qualification        text    default null,
  bio                  text    default null
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
    route_in, study_field, study_detail, qualification, bio
  )
  values (
    add_mentor.full_name, add_mentor.role_title, add_mentor.industry,
    add_mentor.level, add_mentor.experience_label, add_mentor.open_to_talks,
    add_mentor.is_alumnus, add_mentor.alumnus_school_name,
    add_mentor.alumni_contact_ok, add_mentor.public_contact,
    add_mentor.public_contact_kind, add_mentor.publish,
    add_mentor.route_in, add_mentor.study_field,
    add_mentor.study_detail, add_mentor.qualification, add_mentor.bio
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
  p_qualification        text    default null,
  p_bio                  text    default null
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
  if char_length(coalesce(p_bio, '')) > 500 then
    raise exception 'That bio is % characters. The limit is 500.',
      char_length(p_bio) using errcode = '22023';
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
    qualification       => nullif(trim(coalesce(p_qualification, '')), ''),
    bio                 => nullif(trim(coalesce(p_bio, '')), '')
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
  p_qualification        text    default null,
  p_bio                  text    default null
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
  if char_length(coalesce(p_bio, '')) > 500 then
    raise exception 'That bio is % characters. The limit is 500.',
      char_length(p_bio) using errcode = '22023';
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
         qualification       = nullif(trim(coalesce(p_qualification, '')), ''),
         bio                 = nullif(trim(coalesce(p_bio, '')), '')
   where id = p_mentor_id;

  return found;
end;
$$;

revoke all on function public.admin_update_mentor from public, anon;
grant execute on function public.admin_update_mentor to authenticated;


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
  qualification       text,
  bio                 text
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
           m.route_in, m.study_field, m.study_detail, m.qualification, m.bio
      from public.mentors m
      left join public.mentor_contacts c on c.mentor_id = m.id
     order by m.is_published, m.created_at desc;
end;
$$;

revoke all on function public.admin_list_mentors from public, anon;
grant execute on function public.admin_list_mentors to authenticated;

commit;
