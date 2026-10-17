-- ===========================================================================
-- RUN THIS ONCE. It creates a shortcut for adding mentors.
-- ===========================================================================
-- Adding a mentor means writing to two tables: the public profile, and the
-- private contact record that the website cannot read. Doing that by hand is
-- about thirty lines per person and easy to get wrong.
--
-- After you run this file once, adding somebody is one line. See
-- MENTORS-TO-ADD.sql for the sheet you actually fill in.
--
-- Run it in: Supabase dashboard -> SQL Editor -> paste -> Run.
-- It should say "Success. No rows returned."
-- ===========================================================================

create or replace function public.add_mentor(
  -- The six you always need
  full_name            text,
  role_title           text,                    -- exactly as it reads on the card
  industry             industry_slug,           -- see the list in MENTORS-TO-ADD.sql
  level                mentor_level,            -- 'junior' or 'senior'
  contact_email        text,                    -- PRIVATE. Never shown on the site.

  -- Everything below has a safe default, so you can leave it out
  experience_label     text    default null,    -- the small grey line
  open_to_talks        boolean default false,   -- would they come into a school?
  is_alumnus           boolean default false,   -- did they go to a DEIS school?
  alumnus_school_name  text    default null,
  alumni_contact_ok    boolean default false,   -- may over-18s contact them?
  public_contact       text    default null,    -- usually a LinkedIn URL
  public_contact_kind  text    default null,    -- 'linkedin' 'email' or 'other'
  employer             text    default null,    -- private, for your records
  phone                text    default null,    -- private
  notes                text    default null,    -- private. Your vetting record.
  publish              boolean default false    -- FALSE on purpose. See below.
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
    public_contact, public_contact_kind, is_published
  )
  values (
    add_mentor.full_name, add_mentor.role_title, add_mentor.industry,
    add_mentor.level, add_mentor.experience_label, add_mentor.open_to_talks,
    add_mentor.is_alumnus, add_mentor.alumnus_school_name,
    add_mentor.alumni_contact_ok, add_mentor.public_contact,
    add_mentor.public_contact_kind, add_mentor.publish
  )
  returning id into new_id;

  insert into public.mentor_contacts (mentor_id, email, phone, company, notes)
  values (new_id, add_mentor.contact_email, add_mentor.phone,
          add_mentor.employer, add_mentor.notes);

  return new_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- LOCK IT DOWN. This matters.
-- ---------------------------------------------------------------------------
-- Postgres lets anybody run a new function by default, and this one runs with
-- full privileges. Without the next three lines, a visitor to the website
-- could add mentors to your directory. Do not delete them.
-- ---------------------------------------------------------------------------
revoke execute on function public.add_mentor from public;
revoke execute on function public.add_mentor from anon;
revoke execute on function public.add_mentor from authenticated;

comment on function public.add_mentor is
  'Dashboard-only helper. Adds a mentor profile and their private contact
   record together. Staged unpublished unless publish => true.';
