-- ===========================================================================
-- THE ADMIN PAGE
-- ===========================================================================
-- Everything the website could do until now was READ. This is the first thing
-- that WRITES while somebody is signed in, so the gate has to be stricter
-- than the school login.
--
-- In particular: a signed-in school must not be able to add or publish a
-- mentor. Being approved to READ the directory is not permission to change
-- it, and the two checks are deliberately separate.
--
-- Run this whole file once in: Supabase dashboard -> SQL Editor.
-- Then add yourself at the very bottom. Nothing works until you do.
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- 1. Who is an admin.
--    Same shape as the schools table, and the same idea: the gate is this
--    table, not the login. Supabase will email a sign-in link to anybody who
--    asks. An email that is not in here gets a valid session and can do
--    nothing at all.
-- ---------------------------------------------------------------------------
create table if not exists public.admins (
  email      text primary key,
  full_name  text,
  is_active  boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.admins enable row level security;

-- Nobody reads this table from the website. Not even an admin.
-- It is consulted only by the function below, which runs with its own
-- privileges. No policy is created on purpose - that means no access.
revoke all on public.admins from anon, authenticated;


-- ---------------------------------------------------------------------------
-- 2. The gate.
-- ---------------------------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.admins
    where lower(email) = lower(auth.jwt() ->> 'email')
      and is_active
  );
$$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;


-- ---------------------------------------------------------------------------
-- 3. Add a mentor, from the page.
--    A thin wrapper around add_mentor() that refuses anybody who is not an
--    admin. add_mentor() itself stays locked away from the website entirely -
--    this is the only route in.
-- ---------------------------------------------------------------------------
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
  p_notes                text    default null
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

  -- Always staged hidden. Publishing is a separate, deliberate act.
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
    publish             => false
  );
end;
$$;

revoke all on function public.admin_add_mentor from public, anon;
grant execute on function public.admin_add_mentor to authenticated;


-- ---------------------------------------------------------------------------
-- 4. The list, for the admin page.
--    This returns the private contact details, which is exactly why it
--    checks is_admin() first. The website's ordinary queries still cannot
--    see mentor_contacts at all.
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
  created_at          timestamptz
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
           m.is_published, c.email, c.company, c.notes, m.created_at
      from public.mentors m
      left join public.mentor_contacts c on c.mentor_id = m.id
     order by m.is_published, m.created_at desc;
end;
$$;

revoke all on function public.admin_list_mentors from public, anon;
grant execute on function public.admin_list_mentors to authenticated;


-- ---------------------------------------------------------------------------
-- 5. Publish or hide.
--    Nothing here deletes. Somebody who steps back may come back, and a
--    hidden mentor keeps their history and their notes.
-- ---------------------------------------------------------------------------
create or replace function public.admin_set_published(
  p_mentor_id uuid,
  p_published boolean
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
     set is_published = p_published
   where id = p_mentor_id;

  return found;
end;
$$;

revoke all on function public.admin_set_published from public, anon;
grant execute on function public.admin_set_published to authenticated;


-- ---------------------------------------------------------------------------
-- 6. Fix a typo.
--    The public-facing fields only. The private contact record is edited in
--    the dashboard, because it is rarely wrong and changing it is worth the
--    friction.
-- ---------------------------------------------------------------------------
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
  p_public_contact_kind  text    default null
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
         public_contact_kind = nullif(trim(coalesce(p_public_contact_kind, '')), '')
   where id = p_mentor_id;

  return found;
end;
$$;

revoke all on function public.admin_update_mentor from public, anon;
grant execute on function public.admin_update_mentor to authenticated;


-- ===========================================================================
-- 7. ADD YOURSELF. Nothing works until you do.
--    Use the email address you will actually sign in with.
-- ===========================================================================
insert into public.admins (email, full_name)
values ('jack@socialcapital.ie', 'Jack')
on conflict (email) do update set is_active = true;


-- ===========================================================================
-- CHECKING IT
-- ===========================================================================
-- Who can get in:
--   select email, full_name, is_active from public.admins;
--
-- Take someone's access away without deleting the record:
--   update public.admins set is_active = false where email = 'them@example.com';
--
-- Prove the gate holds. Signed in as a SCHOOL, in the browser console on the
-- site, this must fail with "Not permitted":
--   await SC.client.rpc('admin_list_mentors')
-- ===========================================================================
