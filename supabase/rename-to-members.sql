-- ===========================================================================
-- RENAME: "alumni" BECOMES "members"
-- ===========================================================================
-- The network is no longer only former students. A current sixth year who has
-- turned 18 joins on the same basis, approved by their school. "Alumnus" is
-- the wrong word for that cohort, and it is cheaper to fix now - nobody has
-- joined yet - than after a few hundred people have.
--
-- WHAT IS RENAMED
--   table    alumni               -> members
--   function register_alumnus     -> register_member
--   function is_approved_alumnus  -> is_approved_member
--   column   mentors.alumni_contact_ok -> mentors.member_contact_ok
--
-- WHAT IS DELIBERATELY NOT RENAMED
--   mentors.is_alumnus, mentors.alumnus_school_id, mentors.alumnus_school_name
--
--   These mean something different and the word is right for them: this
--   MENTOR is a past pupil of a DEIS school. That is about where the mentor
--   went to school, not about who is allowed into the network, and renaming
--   it would make two different ideas share a word.
--
-- Function bodies that mention any of the above have to be recreated. A
-- Postgres function stores its body as text and resolves names when it runs,
-- so renaming a table does not update the functions that read it - they keep
-- working right up until somebody calls them.
--
-- Run after mentor-bio.sql.
-- ===========================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. The table and the column.
--    Renaming keeps the data, the indexes and the column-level grants - the
--    grants follow the column rather than its name.
-- ---------------------------------------------------------------------------
alter table if exists public.alumni rename to members;
alter table public.mentors rename column alumni_contact_ok to member_contact_ok;

comment on table public.members is
  'Individuals approved by a registered school and aged 18 or over. Includes
   current students who have turned 18, not only people who have left.';


-- ---------------------------------------------------------------------------
-- 2. The row level security policy has to come off first.
--
--    A policy that calls a function depends on it, so the function cannot be
--    dropped underneath it. Postgres offers DROP ... CASCADE, and taking that
--    offer here would be a bad mistake: it drops the policy and does not put
--    it back. This is the policy that lets an approved school read the mentor
--    table at all, and a table with row level security on and no select
--    policy cannot be read by anybody. The directory would have gone blank
--    with no error anywhere to explain it.
--
--    So: drop it, rebuild the functions, put it back.
-- ---------------------------------------------------------------------------
drop policy if exists "approved schools and alumni read mentors" on public.mentors;


-- ---------------------------------------------------------------------------
-- 3. The two gate functions, rebuilt against the new names.
-- ---------------------------------------------------------------------------
drop function if exists public.is_approved_alumnus();
drop function if exists public.register_alumnus(text, text, date);

create or replace function public.is_approved_member()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.members
    where lower(email) = lower(auth.jwt() ->> 'email')
      and is_active
  );
$$;

revoke all on function public.is_approved_member() from public;
grant execute on function public.is_approved_member() to authenticated;


-- Kept working for now so nothing breaks between this migration and the
-- invitation flow, which replaces shared codes with one-time tokens.
create or replace function public.register_member(
  p_code  text,
  p_email text,
  p_dob   date
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  sc public.school_codes%rowtype;
begin
  if p_dob > (current_date - interval '18 years') then
    return 'under_18';
  end if;

  select * into sc from public.school_codes
   where code = upper(trim(p_code)) and is_active;
  if not found then
    return 'bad_code';
  end if;

  insert into public.members (email, school_id, used_code, date_of_birth)
  values (lower(trim(p_email)), sc.school_id, sc.code, p_dob)
  on conflict (lower(email)) do update
    set is_active = true, school_id = excluded.school_id;

  return 'ok';
end;
$$;

revoke all on function public.register_member(text, text, date) from public;
grant execute on function public.register_member(text, text, date) to anon, authenticated;


-- ---------------------------------------------------------------------------
-- 4. The policy again, against the new function name.
-- ---------------------------------------------------------------------------
create policy "approved schools and members read mentors"
  on public.mentors for select
  to authenticated
  using (
    is_published
    and (public.is_approved_school() or public.is_approved_member())
  );

-- The policy on the renamed table travels with it, but its name still said
-- "alumnus". Renaming a policy changes nothing about what it does.
do $$
begin
  if exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'members'
       and policyname = 'alumnus reads own record'
  ) then
    execute 'alter policy "alumnus reads own record" on public.members '
         || 'rename to "member reads own record"';
  end if;
end $$;


-- ---------------------------------------------------------------------------
-- 5. The contact gate.
-- ---------------------------------------------------------------------------
create or replace function public.mentor_contact(p_mentor uuid)
returns table (contact text, kind text)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_approved_member() then
    return;               -- no rows, no error, nothing leaked
  end if;

  return query
    select m.public_contact, m.public_contact_kind
      from public.mentors m
     where m.id = p_mentor
       and m.is_published
       and m.member_contact_ok
       and m.public_contact is not null;
end;
$$;

revoke all on function public.mentor_contact(uuid) from public, anon;
grant execute on function public.mentor_contact(uuid) to authenticated;


-- ---------------------------------------------------------------------------
-- 6. The mentor functions, regenerated from their deployed definitions with
--    only the column name changed.
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
  member_contact_ok    boolean default false,
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
    open_to_talks, is_alumnus, alumnus_school_name, member_contact_ok,
    public_contact, public_contact_kind, is_published,
    route_in, study_field, study_detail, qualification, bio
  )
  values (
    add_mentor.full_name, add_mentor.role_title, add_mentor.industry,
    add_mentor.level, add_mentor.experience_label, add_mentor.open_to_talks,
    add_mentor.is_alumnus, add_mentor.alumnus_school_name,
    add_mentor.member_contact_ok, add_mentor.public_contact,
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
  p_member_contact_ok    boolean default false,
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
    member_contact_ok   => p_member_contact_ok,
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
  p_member_contact_ok    boolean default false,
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
         member_contact_ok   = p_member_contact_ok,
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
  member_contact_ok   boolean,
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
           m.alumnus_school_name, m.member_contact_ok, m.public_contact,
           m.is_published, c.email, c.company, c.notes, m.created_at,
           m.route_in, m.study_field, m.study_detail, m.qualification, m.bio
      from public.mentors m
      left join public.mentor_contacts c on c.mentor_id = m.id
     order by m.is_published, m.created_at desc;
end;
$$;

revoke all on function public.admin_list_mentors from public, anon;
grant execute on function public.admin_list_mentors to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Refuse to finish in a broken state.
--
--    The failure this migration could cause is a silent one: the mentors
--    table with row level security on and no select policy reads as empty to
--    every school, with no error to explain it. Check before committing, so a
--    mistake rolls the whole thing back instead of going live quietly.
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'mentors'
       and policyname = 'approved schools and members read mentors'
  ) then
    raise exception
      'Stopping: the mentors read policy is missing, so no school could see '
      'the directory. Nothing has been changed.';
  end if;

  if to_regclass('public.members') is null then
    raise exception 'Stopping: public.members does not exist.';
  end if;

  if exists (
    select 1 from pg_proc
     where pronamespace = 'public'::regnamespace
       and proname in ('is_approved_alumnus', 'register_alumnus')
  ) then
    raise exception 'Stopping: the old alumnus functions are still here.';
  end if;
end $$;

commit;
